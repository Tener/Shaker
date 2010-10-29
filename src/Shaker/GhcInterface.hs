module Shaker.GhcInterface (
  -- * GHC Compile management
  initializeGhc
  ,ghcCompile
  ,getListNeededPackages
  ,installedPackageIdString 
  -- * module change detection
  ,checkUnchangedSources
  ,isModuleNeedCompilation
 )
 where

import Shaker.Io
import Shaker.Type
import Shaker.SourceHelper

import Data.List
import qualified Data.Map as M

import Control.Monad.Reader(lift )
import Control.Arrow

import Distribution.Package (InstalledPackageId(..))
import LazyUniqFM
import MkIface 
import HscTypes
import Linker
import GHC hiding (parseModule, HsModule)
import GHC.Paths
import Packages (lookupModuleInAllPackages, exposed,  installedPackageId, PackageConfig)
import DynFlags

import System.Directory

import Data.Monoid

type ImportToPackages = [ ( String, [PackageConfig] ) ]

-- | Get the list of unresolved import and 
-- unexposed yet needed packages
getListNeededPackages :: Shaker IO [String]
getListNeededPackages = do
  cpIn <- fmap mconcat getFullCompileCompileInput
  (PackageData map_import_modules list_project_modules) <- lift mapImportToModules
  import_to_packages <- lift $ runGhc (Just libdir) $ do 
    initializeGhc cpIn
    dyn_flags <- getSessionDynFlags
    return $ map ( \ imp -> (imp , lookupModuleInAllPackages dyn_flags . mkModuleName $ imp) ) 
              >>> map ( second (map fst) )
              $ (M.keys map_import_modules \\ list_project_modules) 
  return $ getPackagesToExpose import_to_packages

getPackagesToExpose :: ImportToPackages -> [String]
getPackagesToExpose = map snd
    >>> filter (not . null)
    >>> filter (all (not . exposed) ) 
    >>> map head 
    >>> nubBy (\a b ->  getPackage a == getPackage b ) 
    >>> filter (not . exposed)
    >>> map getPackage 
  where getPackage = installedPackageId >>> installedPackageIdString

installedPackageIdString :: InstalledPackageId -> String
installedPackageIdString (InstalledPackageId v) = v 

initializeGhc :: GhcMonad m => CompileInput -> m ()
initializeGhc cpIn@(CompileInput _ _ procFlags strflags targetFiles) = do   
     modifySession (\h -> h {hsc_HPT = emptyHomePackageTable} )
     dflags <- getSessionDynFlags
     (newFlags,_,_) <- parseDynamicFlags dflags (map noLoc strflags)
     let chgdFlags = configureDynFlagsWithCompileInput cpIn newFlags
     _ <- setSessionDynFlags $ procFlags chgdFlags
     target <- mapM (`guessTarget` Nothing) targetFiles
     setTargets target

-- | Check of the module need to be recompile.
-- Modify ghc session by adding the module iface in the homePackageTable
isModuleNeedCompilation :: (GhcMonad m) => 
  [FilePath] -- ^ List of modified files
  -> ModSummary  -- ^ ModSummary to check
  -> m Bool -- ^ Result : is the module need to be recompiled
isModuleNeedCompilation modFiles ms = do
    hsc_env <- getSession
    source_unchanged <- liftIO $ checkUnchangedSources modFiles ms
    (recom, mb_md_iface ) <- liftIO $ checkOldIface hsc_env ms source_unchanged Nothing
    case mb_md_iface of 
        Just md_iface -> do 
                let module_name = (moduleName . mi_module) md_iface 
                    the_hpt = hsc_HPT hsc_env 
                    home_mod_info = HomeModInfo {hm_iface = md_iface, hm_details = emptyModDetails, hm_linkable = Nothing }
                    newHpt = addToUFM  the_hpt module_name home_mod_info
                modifySession (\h -> h {hsc_HPT = newHpt} )
                return recom 
        _ -> return True

checkUnchangedSources :: [FilePath] -> ModSummary ->  IO Bool
checkUnchangedSources fps ms = checkUnchangedSources' fps $ (ml_hs_file . ms_location) ms

checkUnchangedSources' :: [FilePath] -> Maybe FilePath ->  IO Bool
checkUnchangedSources' _ Nothing = return False
checkUnchangedSources' modifiedFiles (Just src) = do 
   canonical_modFiles <- liftIO $ mapM canonicalizePath modifiedFiles
   cano_src <- canonicalizePath src 
   return $ cano_src `notElem` canonical_modFiles

-- | Configure and load targets of compilation. 
-- It is possible to exploit the compilation result after this step.
ghcCompile :: GhcMonad m => CompileInput -> m SuccessFlag
ghcCompile cpIn = do   
     initializeGhc cpIn
     dflags <- getSessionDynFlags
     liftIO $ unload dflags []
     load LoadAllTargets

-- | Change the dynflags with information from the CompileInput like importPaths 
-- and .o and .hi fileListenInfoDirectory
configureDynFlagsWithCompileInput :: CompileInput -> DynFlags -> DynFlags 
configureDynFlagsWithCompileInput cpIn dflags = dflags{
    importPaths = sourceDirs
    ,objectDir = Just compileTarget
    ,hiDir = Just compileTarget
  }
  where compileTarget = compileInputBuildDirectory cpIn
        sourceDirs = compileInputSourceDirs cpIn

