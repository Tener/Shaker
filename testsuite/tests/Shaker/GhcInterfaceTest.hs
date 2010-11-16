module Shaker.GhcInterfaceTest
 where

import Control.Monad.Reader hiding (liftIO)
import Data.List
import Data.Monoid
import Shaker.Config
import Shaker.GhcInterface
import Shaker.Type
import Test.HUnit

testListNeededPackages :: Assertion
testListNeededPackages = do
  let cpIn = mempty {compileInputCommandLineFlags = ["-hide-all-packages"]}
  let shIn = defaultInput { shakerCompileInputs = [cpIn]  }
  list_needed_imports <- runReaderT getListNeededPackages shIn
  any (isPrefixOf "bytestring") list_needed_imports @? show list_needed_imports

