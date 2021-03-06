{-# LANGUAGE OverloadedStrings #-}

module Main where

import Brick.BChan
  ( BChan,
    newBChan,
    writeBChan,
  )
import Brick.Main
  ( App (..),
    customMain,
    showCursorNamed,
  )
import Control.Concurrent
  ( forkIO,
    threadDelay,
  )
import Control.Exception
  ( IOException,
    catch,
  )
import Controller (routeEvent)
import Graphics.Vty
import qualified Graphics.Vty as V
import Lens.Micro ((^.))
import Loading
  ( getOptions,
    startNewGame,
  )
import Model.Types
  ( AsciiMaze,
    GameSt,
    Name (..),
    Options (..),
    Time,
    TimeEvent (..),
  )
import qualified Model.Types as T
import Model.Utilities
  ( formatHighScore,
    readHighScores,
    tickPeriod,
  )
import Resources (getAsciiMaze)
import System.Directory
  ( createDirectory,
    doesDirectoryExist,
    getHomeDirectory,
  )
import System.Environment (getArgs)
import System.Posix.Env (putEnv)
import System.Random (getStdGen)
import View.Core (attributes)
import View.View (drawUI)

---------------------------------------------------------------------
-- Entry point and Brick App definition

main :: IO ()
main = do
  eitherOpts <- getOptions <$> getArgs
  case eitherOpts of
    Left msg -> putStrLn msg
    Right opts ->
      initGame opts
        >>= runGame
        >>= stopGame

app :: App GameSt TimeEvent Name
-- ^ Define the value of the Brick App type.
app =
  App
    { appDraw = drawUI,
      appHandleEvent = routeEvent,
      appAttrMap = const attributes,
      appStartEvent = return,
      appChooseCursor = const (showCursorNamed HighScoreEdit)
    }

---------------------------------------------------------------------
-- Initialization and timers

runTimer :: BChan TimeEvent -> Time -> IO ()
runTimer chan t = do
  writeBChan chan (Tick t)
  threadDelay tickPeriod
  runTimer chan (t + tickPeriod)

initGame :: Options -> IO GameSt
initGame opts = do
  putEnv $ "TERM=" ++ opts ^. T.terminal
  gen <- getStdGen
  hsPath <- (++ "/.config/pmgame/high_scores") <$> getHomeDirectory
  scores <- readHighScores <$> readFileEither hsPath
  mazeStr <- getFirstAsciiMaze (opts ^. T.firstmaze) (opts ^. T.firstlevel)
  return $ mazeStr >>= startNewGame gen scores (opts ^. T.firstlevel)

---------------------------------------------------------------------
-- Running the game

runGame :: GameSt -> IO GameSt
runGame newGame = do
  chan <- newBChan 10 :: IO (BChan TimeEvent)
  defaultConfig' <- V.standardIOConfig
  vty <- mkVty defaultConfig'
  _ <- forkIO $ runTimer chan 0
  customMain vty (V.mkVty defaultConfig') (Just chan) app newGame

---------------------------------------------------------------------
-- Shutting down the game
-- If there was an error, print it to the terminal; otherwise, save
-- the new list of high scores. High scores are saved in the pmgame
-- directory, which is created in the user's ~/.config directory.
-- If there is no ~/.config directory, the user is informed, no
-- pmgame directory is created and the high scores are not saved.

stopGame :: GameSt -> IO ()
stopGame (Left msg) = putStrLn msg
stopGame (Right gm) = do
  configDir <- (++ "/.config/pmgame") <$> getHomeDirectory
  exists <- doesDirectoryExist configDir
  if exists
    then
      let xs = concatMap formatHighScore $ gm ^. T.highscores
       in writeFile (configDir ++ "/high_scores") xs
    else handleMissingConfig . Right $ gm

handleMissingConfig :: GameSt -> IO ()
handleMissingConfig gmst = do
  path <- (++ "/.config") <$> getHomeDirectory
  exists <- doesDirectoryExist path
  if exists
    then do
      createDirectory $ path ++ "/pmgame"
      stopGame gmst
    else stopGame . Left $ noConfigMessage

noConfigMessage :: String
noConfigMessage = concat msg
  where
    msg =
      [ "There is no .config directory in your home directory.\n",
        "Therefore, the high scores cannot be saved. Create the\n",
        "directory ~/.config to save future high scores."
      ]

---------------------------------------------------------------------
-- Helper functions

getFirstAsciiMaze :: Maybe FilePath -> Int -> IO (Either String AsciiMaze)
-- ^ The first maze played can be user-defined.
getFirstAsciiMaze Nothing lvl = return . Right . getAsciiMaze $ lvl
getFirstAsciiMaze (Just fp) _ = readFileEither fp

readFileEither :: FilePath -> IO (Either String String)
-- ^ Read a file converting IO exceptions to Left String values.
readFileEither fp = catch (Right <$> readFile fp) hndlErr
  where
    hndlErr :: IOException -> IO (Either String String)
    hndlErr _ = return . Left $ "Error: cannot open file '" ++ fp ++ "'!"
