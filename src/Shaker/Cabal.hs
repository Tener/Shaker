module Shaker.Cabal
 where

import Distribution.Simple.Configure
import Distribution.Simple.LocalBuildInfo
import Distribution.PackageDescription
import Distribution.Compiler
import Shaker.Type
import Shaker.Config
import DynFlags


data CabalInfo = CabalInfo {
    sourceDir :: [String]
    ,modules :: [String]
    ,compileOption :: [String]
    ,packageType :: PackageType
  }
 deriving (Show)

data PackageType = ExecutableType | LibraryType
 deriving (Show)
 

cabalInput :: LocalBuildInfo -> ShakerInput 
cabalInput lbi = ShakerInput {
  compileInput = cabalCompileInput $ getCabalLibInformation lbi,
  listenerInput = defaultListenerInput,
  pluginMap = defaultPluginMap,
  commandMap = defaultCommandMap
  }

cabalCompileInput :: CabalInfo -> CompileInput
cabalCompileInput cabInf = CompileInput (cabalCompileFlags cabInf)  $ compileOption cabInf

cabalCompileFlags :: CabalInfo -> (DynFlags -> DynFlags)
cabalCompileFlags cabInfo = \a-> a  {
    importPaths = sourceDir cabInfo
    ,outputFile = Just "target/Main"
    ,objectDir = Just "target"
    ,hiDir = Just "target"
    ,ghcLink = NoLink
  } 

getCabalLibInformation :: LocalBuildInfo -> CabalInfo
getCabalLibInformation lbi = 
 case library (localPkgDescr lbi) of
      Nothing -> defaultCabalInfo
      Just lib -> let myLibBuildInfo = libBuildInfo lib in
          CabalInfo {
            sourceDir = hsSourceDirs myLibBuildInfo
            ,compileOption = getCompileOptions myLibBuildInfo
            ,modules = map show $ exposedModules lib
            ,packageType = LibraryType
          }


getCabalExecutableInformation :: LocalBuildInfo -> [CabalInfo]
getCabalExecutableInformation lbi = 
 map parseToCabalInfo $ executables (localPkgDescr lbi) 

parseToCabalInfo :: Executable -> CabalInfo
parseToCabalInfo = undefined

getCompileOptions :: BuildInfo -> [String]
getCompileOptions myLibBuildInfo = 
  case lookup GHC (options myLibBuildInfo) of
       Nothing -> []
       Just res -> res 
 
defaultCabalInfo :: CabalInfo
defaultCabalInfo = CabalInfo ["src"] [] ["-Wall"] LibraryType

readConf :: IO (LocalBuildInfo)
readConf = getPersistBuildConfig "dist"

