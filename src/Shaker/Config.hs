module Shaker.Config
 where

import Shaker.Type

defaultConfig :: ShakerConfig 
defaultConfig = ShakerConfig {
  cfImportPaths = ["src/","testsuite/tests/"],
  cfDelay = 2*10^6
}

