-- | Conductor is responsible to control the command-line listener, 
-- the listener manager and the action to execute
module Shaker.Conductor(
 initThread
)
  where

import Shaker.Type
import Control.Monad
import Control.Concurrent
import Shaker.Listener
import Shaker.Cli
import qualified Data.Map as M
import Control.Monad.Reader
 
-- | Initialize the master thread 
-- Once the master thread is finished, all input threads are killed
initThread :: InputState -> Shaker IO()
initThread inputState = do
  act <- asks $ runReaderT (getInput inputState) 
  procId <- lift $ forkIO $ forever act
  mainThread inputState 
  lift $ killThread procId
 
-- | The main thread. 
-- Loop until a Quit action is called
mainThread :: InputState -> Shaker IO()
mainThread st@(InputState inputMv tokenMv) = do
  _ <- lift $ tryPutMVar tokenMv 42
  cmd <- lift $ takeMVar inputMv
  executeCommand cmd  
  case cmd of
       Command _ Quit -> return ()
       _ ->  mainThread st

-- | Continuously execute the given action until a keyboard input is done
listenManager :: Shaker IO() -> Shaker IO()
listenManager fun = do
  shIn <- ask 
  lift $ action shIn 
  where action shIn = do
          -- Setup keyboard listener
          endToken <- newEmptyMVar 
          procCharListener <- forkIO $ getChar >>= putMVar endToken
          -- Setup source listener
          listenState <- initialize (listenerInput shIn)
          -- Run the action
          procId <-  forkIO $ forever $ threadExecutor listenState (runReaderT fun shIn)
          _ <- readMVar endToken 
          mapM_ killThread  $  [procId,procCharListener] ++ threadIds listenState
  
-- | Execute the given action when the modified MVar is filled
threadExecutor :: ListenState -> IO() -> IO ThreadId
threadExecutor listenState fun = takeMVar (modifiedFiles listenState) >> forkIO fun 

-- | Execute Given Command in a new thread
executeCommand :: Command -> Shaker IO()
executeCommand (Command OneShot act) = executeAction act 
executeCommand (Command Continuous act) = listenManager ( executeAction act ) >> return () 

-- | Execute given action
executeAction :: Action -> Shaker IO()
executeAction act = do
    thePluginMap <- asks pluginMap
    case M.lookup act thePluginMap of
      Just action -> action 
      Nothing -> lift $ putStrLn $ "action "++ show act ++" is not registered"

