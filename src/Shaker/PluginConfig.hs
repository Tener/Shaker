-- | Register available actions and how they will be called
module Shaker.PluginConfig
 where

import qualified Data.Map as M (fromList)
import Shaker.Type
import Shaker.Action.Test
import Shaker.Action.Compile
import Shaker.Action.Standard

-- | The default plugin map contains mapping for compile, help and exit action 
defaultPluginMap :: PluginMap
defaultPluginMap = M.fromList $ map (\(a,b) -> (a, runStartAction >> b >> runEndAction)) list
  where list = [
                (Compile,runCompile ),
                (FullCompile,runFullCompile ),
                (Help,runHelp),
--                (Execute,runExecute),
                (QuickCheck,runQuickCheck),
                (IntelligentQuickCheck,runIntelligentQuickCheck),
                (IntelligentHUnit ,runIntelligentHUnit),
                (QuickHUnit, runQuickHUnit),
                (IntelligentQuickHUnit, runIntelligentQuickHUnit ),
                (HUnit,runHUnit),
                (Clean,runClean),
                (Quit,runExit)
              ]

defaultCommandMap :: CommandMap 
defaultCommandMap = M.fromList list
  where list = [
            ("Compile",Compile),
            ("FullCompile",FullCompile),
            ("Help", Help),
--            ("Execute", Execute),
            ("QuickCheck",QuickCheck),
            ("IQuickCheck",IntelligentQuickCheck),
            ("IHUnit",IntelligentHUnit),
            ("HUnit",HUnit),
            ("QuickHUnit", QuickHUnit),
            ("IQuickHUnit", IntelligentQuickHUnit),
            ("Clean",Clean),
            ("q",Quit),
            ("Quit",Quit)
          ]

