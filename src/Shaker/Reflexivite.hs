module Shaker.Reflexivite(
  ModuleMapping(..)
  ,RunnableFunction(..)
  ,runReflexivite
  ,runFunction
  ,collectChangedModules
  ,checkUnchangedSources
  ,isModuleNeedCompilation
  -- * Template haskell generator
  ,listHunit
  ,listProperties
)
 where

import OccName (occNameString)
import Name (nameOccName)
import Var (varName)
import Data.List
import Data.Maybe
import GHC
import GHC.Paths
import Outputable
import MkIface 
import Shaker.Type 
import Shaker.Action.Compile
import Shaker.SourceHelper
import Unsafe.Coerce
import MonadUtils
import Control.Monad.Reader(runReader,runReaderT,asks, lift, filterM)
import Control.Arrow
import Language.Haskell.TH

-- | Mapping between module name (to import) and test to execute
data ModuleMapping = ModuleMapping {
  cfModuleName :: String -- ^ Complete name of the module 
  ,cfHunitName :: [String] -- ^ Hunit test function names
  ,cfPropName :: [String] -- ^ QuickCheck test function names
 }
 deriving Show

data RunnableFunction = RunnableFunction {
  cfModule :: [String]
  ,cfFunctionName :: String -- The function name. Should have IO() as signature
}
 deriving Show

collectChangedModules :: Shaker IO [ModSummary]
collectChangedModules = do 
  cpList <- asks compileInputs 
  let cpIn = mergeCompileInputsSources cpList
  cfFlList <- lift $ constructCompileFileList cpIn
  modInfoFiles <- asks modifiedInfoFiles
  let modFilePaths = (map fileInfoFilePath modInfoFiles)
  lift $ runGhc (Just libdir) $ do 
            _ <- initializeGhc $ runReader (setAllHsFilesAsTargets cpIn >>= removeFileWithMain ) cfFlList
            modSummaries <- depanal [] False
            -- liftIO $ putStrLn $ show modInfoFiles
            toRecompile <- filterM (isModuleNeedCompilation modFilePaths) modSummaries
            _ <- liftIO $ mapM (putStrLn . showPpr . ms_mod) toRecompile
            return toRecompile
            -- mapM getModuleMapping modSummaries 

isModuleNeedCompilation :: (GhcMonad m) => [FilePath] -> ModSummary -> m Bool
isModuleNeedCompilation modFiles ms = do
    hsc_env <- getSession
    (recom, _ ) <- liftIO $ checkOldIface hsc_env ms source_unchanged Nothing
    liftIO $ putStrLn $ "Module : " ++ (showPpr . moduleName . ms_mod) ms  ++ "\t ToRecompile : "++ show recom
--    liftIO $ putStrLn $ "Hi files : " ++ (ml_hi_file . ms_location ) ms  ++ "\t ToRecompile : "++ show recom
    return recom 
  where source_unchanged = checkUnchangedSources modFiles ms

checkUnchangedSources :: [FilePath] -> ModSummary ->  Bool
checkUnchangedSources modifiedFiles ms = check hsSource
  where hsSource = (ml_hs_file . ms_location) ms
        check Nothing = False
        check (Just src) = not $ src `elem` modifiedFiles

-- | Collect all non-main modules with their test function associated
runReflexivite :: Shaker IO [ModuleMapping]
runReflexivite = do
  cpList <- asks compileInputs 
  let cpIn = mergeCompileInputsSources cpList
  cfFlList <- lift $ constructCompileFileList cpIn
  lift $ runGhc (Just libdir) $ do 
            _ <- ghcCompile $ runReader (setAllHsFilesAsTargets cpIn >>= removeFileWithMain >>=removeFileWithTemplateHaskell) cfFlList
            modSummaries <- getModuleGraph
            mapM getModuleMapping modSummaries 

-- | Compile, load and run the given function
runFunction :: RunnableFunction -> Shaker IO()
runFunction (RunnableFunction funModuleName fun) = do
  cpList <- asks compileInputs 
  let cpIn = mergeCompileInputsSources cpList
  cfFlList <- lift $ constructCompileFileList cpIn
  dynFun <- lift $ runGhc (Just libdir) $ do
         _ <- ghcCompile $ runReader (setAllHsFilesAsTargets cpIn >>= removeFileWithMain ) cfFlList
         configureContext funModuleName
         value <- compileExpr fun
         do let value' = unsafeCoerce value :: a
            return value'
  _ <- lift dynFun
  return () 
  where 
        configureContext [] = getModuleGraph >>= \mGraph ->  setContext [] $ map ms_mod mGraph
        configureContext imports = mapM (\a -> findModule (mkModuleName a)  Nothing ) imports >>= \m -> setContext [] m

-- | Collect module name and tests name for the given module
getModuleMapping :: (GhcMonad m) => ModSummary -> m ModuleMapping
getModuleMapping  modSum = do 
  mayModuleInfo <- getModuleInfo $  ms_mod modSum
  let props = getQuickCheckFunction mayModuleInfo
  let hunits = getHunitFunctions mayModuleInfo
  return $ ModuleMapping modName hunits props
  where modName = (moduleNameString . moduleName . ms_mod) modSum        
       
getQuickCheckFunction :: Maybe ModuleInfo -> [String]
getQuickCheckFunction = getFunctionNameWithPredicate ("prop_" `isPrefixOf`) 

getHunitFunctions :: Maybe ModuleInfo -> [String]
getHunitFunctions = getFunctionTypeWithPredicate (== "Test.HUnit.Base.Test") 

getFunctionTypeWithPredicate :: (String -> Bool) -> Maybe ModuleInfo -> [String]
getFunctionTypeWithPredicate _ Nothing = []
getFunctionTypeWithPredicate predicat (Just modInfo) = map snd $ filter ( predicat . fst)  typeList
   where idList = getIdList modInfo
         typeList = map ((showPpr . idType) &&& getFunctionNameFromId ) idList 

getFunctionNameWithPredicate :: (String -> Bool) -> Maybe ModuleInfo -> [String]
getFunctionNameWithPredicate _ Nothing = []
getFunctionNameWithPredicate predicat (Just modInfo) = filter predicat nameList
   where idList = getIdList modInfo
         nameList = map getFunctionNameFromId idList 

getFunctionNameFromId :: Id -> String
getFunctionNameFromId = occNameString . nameOccName . varName

getIdList :: ModuleInfo -> [Id]
getIdList modInfo = mapMaybe tyThingToId $ modInfoTyThings modInfo

tyThingToId :: TyThing -> Maybe Id
tyThingToId (AnId tyId) = Just tyId
tyThingToId _ = Nothing
 

getQuickCheckProperty :: [ModuleMapping] -> [Exp]
getQuickCheckProperty = concatMap getQuickCheckProperty'

getQuickCheckProperty' :: ModuleMapping -> [Exp]
getQuickCheckProperty' modMap = map getSingleQuickCheck $ cfPropName modMap

getSingleQuickCheck :: String -> Exp
getSingleQuickCheck propName = InfixE (Just printName) (VarE $ mkName ">>") (Just quickCall)
  where quickCall = (AppE (VarE $ mkName "quickCheck" ) . VarE . mkName) propName
        printName = AppE (VarE $ mkName "putStrLn") (LitE (StringL propName)) 

getHunit :: [ModuleMapping] -> [Exp]
getHunit = concatMap getHunit'

getHunit' :: ModuleMapping -> [Exp]
getHunit' modMap = map (VarE . mkName) $ cfHunitName modMap

-- | List the quickeck properties of the project.
-- see "Shaker.TestTH"
listProperties :: ShakerInput -> ExpQ
listProperties shIn = do
  modMaps <- runIO $ runReaderT runReflexivite shIn
  return $ ListE $ getQuickCheckProperty modMaps

-- | List all test case of the project.
-- see "Shaker.TestTH"
listHunit :: ShakerInput -> ExpQ
listHunit shIn = do 
  modMaps <- runIO $ runReaderT runReflexivite shIn
  return $ ListE $ getHunit modMaps

