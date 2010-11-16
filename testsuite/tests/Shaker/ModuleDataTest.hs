module Shaker.ModuleDataTest
 where 

import Control.Monad.Reader
import Data.List
import Data.Monoid 
import Shaker.CommonTest
import Shaker.ModuleData
import Shaker.Type
import Test.HUnit

testReadWriteModuleData :: Assertion
testReadWriteModuleData = do
  moduleData <- getParsedModule
  shIn <- testShakerInput
  runReaderT (writeModuleData moduleData) shIn
  let testFile = "testsuite/tests/Shaker/ModuleDataTest.hs"
  readModuleData <- runReaderT (readModuleDataIfExist testFile) shIn
  Just moduleData == readModuleData @? "Module datas should be equals, got " ++ show moduleData ++ " and " ++ show readModuleData

testGroupModuleData :: Assertion
testGroupModuleData = do 
  parsedMod <- fmap groupByValidTargets (parseModuleData [ mempty ])
  let res = filter ( any ( \ md -> "/noHsSource.hs" `isSuffixOf` moduleDataFileName md) ) parsedMod
  length res == 1 @? show res
  
testNubModuleData :: Assertion
testNubModuleData = do
  parsedMod <- fmap nub (parseModuleData [ mempty ])
  let res = filter ( \ md -> "/CabalTest.hs" `isSuffixOf` moduleDataFileName md) parsedMod
  length res == 1 @? show res

testGetNonMain :: Assertion
testGetNonMain = do
 shIn <- testShakerInput
 cpIn <- runReaderT getNonMainCompileInput shIn
 let filtered = filter (isSuffixOf "CabalTest.hs"  ) (compileInputTargetFiles cpIn )
 length filtered ==1 @? show filtered

testModuleDataFileName :: Assertion
testModuleDataFileName = do
  modData <- getParsedModule
  "ModuleDataTest.hs" `isSuffixOf` moduleDataFileName modData @? show modData

testModuleHasMain :: Assertion
testModuleHasMain = do
  (parsedMod:_) <- parseModuleData [ mempty {fileListenInfoDir ="prog" } ]
  moduleDataHasMain parsedMod @? "Should have main, got " ++ show parsedMod

testGroupByMethodUniqueGroup :: Assertion
testGroupByMethodUniqueGroup = do
  parsedMod <- parseModuleData [ mempty {fileListenInfoDir ="testsuite/tests/resources/sameFileInDifferentsModules" } ]
  let res = groupByValidTargets parsedMod 
  length res == 1 @? "Should have one group, got " ++ show res

testGroupByMethodMultipleGroups :: Assertion
testGroupByMethodMultipleGroups = do
  parsedMod <- parseModuleData [ mempty {fileListenInfoDir ="testsuite/tests/resources/" } ]
  let res = groupByValidTargets parsedMod 
  let filtered = map ( filter (\a -> "A" == moduleDataName a  ) ) res
  all (\a -> length a <= 1) filtered @? "Should have no group with more than one A module, got " ++ show filtered

testModuleDataHasTests :: Assertion
testModuleDataHasTests = do 
  modData <- getParsedModule
  hsModuleDataHasTest modData @? show modData

getParsedModule :: IO ModuleData 
getParsedModule = fmap head ( parseModuleData [ mempty { fileListenInfoDir = "testsuite/tests/Shaker", fileListenInfoInclude = [".*ModuleDataTest.hs"]  } ] )
