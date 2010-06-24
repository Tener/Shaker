module Shaker.IoTest
 where

import Shaker.Type
import Shaker.Io
import System.Directory
import System.Time
import Control.Monad
import Data.List
import Test.QuickCheck 
import Test.QuickCheck.Monadic 
import Shaker.Properties

aTimeDiff :: TimeDiff
aTimeDiff = TimeDiff { tdYear = 0, tdMonth = 0, tdDay = 0, tdHour =0, tdMin=0, tdSec = -1, tdPicosec =0 }

modifyFileInfoClock :: FileInfo -> FileInfo
modifyFileInfoClock (FileInfo fp cl) = FileInfo fp (addToClockTime aTimeDiff cl)

testListFiles :: FileListenInfo -> ([FilePath] -> [FilePath] -> Bool) -> Property
testListFiles fli pred = monadicIO test
  where test = run (listFiles fli{ignore= []}) >>= \lstFile ->
               run (listFiles fli) >>= \r->
               assert $ pred lstFile r 

prop_listFiles :: FileListenInfo -> Property
prop_listFiles fli = testListFiles fli{ignore=[]} (\a b -> length b>2)

prop_listFilesWithIgnoreAll :: FileListenInfo -> Property
prop_listFilesWithIgnoreAll fli = testListFiles fli{ignore= [".*"]} (\a b -> b==[])

prop_listFilesWithIgnore :: FileListenInfo -> Property
prop_listFilesWithIgnore fli = testListFiles fli{ignore= ["\\.$"]} (\a b-> length a == length b + 2)

testModifiedFiles :: FileListenInfo -> ([FileInfo] -> [FileInfo]) -> ([FileInfo] -> [FileInfo] ->Bool) -> Property
testModifiedFiles fli proc pred= monadicIO test
  where test = run (getCurrentFpCl fli) >>= \curList ->    
               run (listModifiedAndCreatedFiles fli (proc curList)) >>= \newList ->
               assert $ pred curList newList 

prop_listModifiedFiles fli = 
  testModifiedFiles fli (map modifyFileInfoClock) (\a b -> length a == length b)

prop_listCreatedFiles fli = 
  testModifiedFiles fli (init) (\a b -> length b==1)

prop_listModifiedAndCreatedFiles fli = 
  testModifiedFiles fli ((map modifyFileInfoClock) . init) (\a b -> length a == length b)

