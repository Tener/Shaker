module Shaker.CommonTest
 where 

import System.Directory
import Test.HUnit
import Control.Exception
import Shaker.Type
import Shaker.Config
import Shaker.SourceHelper
import Shaker.Cabal.CabalInfo

import Control.Monad.Reader(runReader)

import GHC
import GHC.Paths

runTestOnDirectory :: FilePath -> Assertion -> Assertion
runTestOnDirectory fp fun = do
  oldDir <- getCurrentDirectory 
  setCurrentDirectory fp
  finally fun (setCurrentDirectory oldDir)

testCompileInput ::IO CompileInput 
testCompileInput = defaultCabalInput >>= return . mergeCompileInputsSources . compileInputs

initializeEmptyCompileInput :: CompileInput 
initializeEmptyCompileInput = CompileInput {
  cfSourceDirs = []
  ,cfDescription = ""
  ,cfCompileTarget = ""
  ,cfDynFlags = id
  ,cfCommandLineFlags =[]
  ,cfTargetFiles = []
}

testShakerInput :: ShakerInput
testShakerInput = defaultInput {
  compileInputs = [defaultCompileInput {
       cfCommandLineFlags = ["-package ghc"]
     }]
}

compileProject :: IO(CompileInput, [CompileFile])
compileProject = do
  let cpIn = head . compileInputs $ testShakerInput
  cfFlList <- constructCompileFileList cpIn
  _ <- runGhc (Just libdir) $ 
      ghcCompile $ runReader (fillCompileInputWithStandardTarget cpIn) cfFlList
  return (cpIn, cfFlList)


