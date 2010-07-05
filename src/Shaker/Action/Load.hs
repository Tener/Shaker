module Shaker.Action.Load
 where

import Language.Haskell.Interpreter
import Control.Monad
import Control.Monad.Trans
          
--runLoadFiles :: [FilePath] -> 
runLoadFiles = runInterpreter . loadFiles

loadFiles :: [FilePath] -> Interpreter()
loadFiles files = 
  set [searchPath := ["./src/","./testsuite/tests"] ] >>
  loadModules files >>
  getLoadedModules >>= liftIO . print


