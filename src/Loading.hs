{-# LANGUAGE OverloadedStrings #-}
module Loading
    (
    -- files and maze numbers
      getMazeFile
    , highScoresFile
    , mazeNumber
    -- Game initialization and level transitioning
    , advanceLevel
    , startNewGame
    , restartNewGame
    -- Working with strings encoding high score information
    , readHighScores
    , showHighScore
    -- Parsing command line arguments into game options
    , getOptions
    ) where

import qualified Data.Matrix           as M
import qualified Data.Vector           as V
import qualified Model.Types           as T
import qualified System.Console.GetOpt as O
import qualified Resources             as R
import Text.Read                            ( readMaybe             )
import Brick.Widgets.Edit                   ( editor                )
import Data.List                            ( find, foldl'
                                            , intercalate, sort
                                            , sortOn                )
import Lens.Micro                           ( (&), (^.), (.~), (%~)
                                            , over, set             )
import System.Random                        ( randomR, StdGen       )
import Model.Utilities                      ( fruitDuration
                                            , newMessage
                                            , powerDuration
                                            , tickPeriod
                                            , toMicroSeconds        )
import Model.Types                          ( Direction     (..)
                                            , Fruit         (..)
                                            , FruitName     (..)
                                            , Game          (..)
                                            , GameSt        (..)
                                            , Ghost         (..)
                                            , GhostName     (..)
                                            , GhostState    (..)
                                            , HighScore     (..)
                                            , Items         (..)
                                            , Maze          (..)
                                            , MazeString    (..)
                                            , Mode          (..)
                                            , Name          (..)
                                            , Options       (..)
                                            , PacMan        (..)
                                            , Point         (..)
                                            , Score         (..)
                                            , Tile          (..)
                                            , Time          (..)    )

---------------------------------------------------------------------
---------------------------------------------------------------------
-- This module contains only pure code and handles the initialization
-- of levels, transitioning between levels, parsing of maze files and
-- parsing of command line arguments read as options.

-- =============================================================== --
-- Helper types

-- |Raw MazeString where each ascii charcter has been indexed by the
-- row and column it represents in the level maze.
type IndexedMaze = [(Point, Char)]

-- =============================================================== --
-- List of levels and associated maze files

getMazeFile :: Int -> FilePath
-- ^Maps level numbers to files.
getMazeFile lvl
    | lvl > 0 = "dev/maze" ++ m ++ ".txt"
    | lvl < 1 = "dev/maze-testing/testing" ++ m ++ ".txt"
    where m = show . abs . mazeNumber $ lvl

mazeNumber :: Int -> Int
-- ^Maps level numbers to maze numbers.
mazeNumber n
    | n > 0     = rem (m - 1) 5 + 1
    | otherwise = n
    where m = quot ( rem n 2 + n ) 2

highScoresFile :: FilePath
-- ^File where high scores are stored.
highScoresFile = "dev/high_scores.txt"

-- =============================================================== --
-- Game initialization and level transitioning

startNewGame :: StdGen -> [HighScore] -> Int -> MazeString -> GameSt
-- ^Complete intialization of a new game state based on a standard
-- generator, a list of high scores, a level number to start at and
-- a maze string for the first level to play.
startNewGame r0 scores level asciiMaze = do
    xs   <- indexMazeString asciiMaze
    m    <- loadMaze xs
    pman <- loadPacMan xs
    gs   <- mapM ( loadGhost xs ) "pbic"
    (mbFruit, r1) <- loadFruit r0 level xs
    return Game { _maze       = m
                , _items      = Items 0 0 [] []
                , _rgen       = r1
                , _pacman     = pman
                , _ghosts     = sort gs
                , _fruit      = mbFruit
                , _mode       = StartScreen
                , _level      = level
                , _npellets   = countPellets xs
                , _oneups     = 2
                , _time       = 0
                , _pwrmult    = 2
                , _dtime      = 0
                , _pwrtime    = powerDuration level
                , _msg        = newMessage "Ready!"
                , _highscores = reverse . sortOn snd $ scores
                , _hsedit     = editor HighScoreEdit ( Just 1 ) ""
                }

advanceLevel :: Game -> MazeString -> GameSt
-- ^Reintialize the game state upon starting a new level. A complete
-- initialization is performed with the updated level and maze, and
-- then further updated with those praameters that should carry over
-- such as the time and remaining number of oneups.
advanceLevel gm asciiMaze = do
    let nxtLvl = succ $ gm ^. T.level
        scores = gm ^. T.highscores
        gen    = gm ^. T.rgen
    nxtGame <- startNewGame gen scores nxtLvl asciiMaze
    return $ nxtGame & T.mode   .~ Running
                     & T.items  .~ ( gm ^. T.items  )
                     & T.oneups .~ ( gm ^. T.oneups )
                     & T.time   .~ ( gm ^. T.time   )

restartNewGame :: Game -> MazeString -> GameSt
-- ^Reinitialize the game after player has lost all lives. A complete
-- initialization is performed and just the time is updated as well
-- as the play mode to return the player back to the start screen.
restartNewGame gm asciiMaze = do
    let scores = gm ^. T.highscores
        gen    = gm ^. T.rgen
    newGame <- startNewGame gen scores 1 asciiMaze
    return $ newGame & T.mode .~ StartScreen
                     & T.time .~ ( gm ^. T.time )

-- =============================================================== --
-- Parsing level files

---------------------------------------------------------------------
-- Utilities

indexMazeString :: MazeString -> Either String IndexedMaze
-- ^Index a MazeString to get an IndexedMaze string making sure that
-- it is rectangular.
indexMazeString s
    | isRect    = Right . zip indxs . concat $ ss
    | otherwise = Left "Maze is not rectangular"
    where ss     = lines s
          nr     = length ss
          nc     = length . head $ ss
          isRect = all ( (== nc). length ) ss
          indxs  = [ (r,c) | r <- [1..nr], c <- [1..nc] ]

getDims :: IndexedMaze -> (Int, Int)
-- ^Rows and columns of the maze that an IndexedMaze represents.
getDims xs = (maximum rs, maximum cs)
    where (rs,cs) = unzip . fst . unzip $ xs

countPellets :: IndexedMaze -> Int
-- ^Get number of pellets and power pellets from an IndexedMaze.
countPellets = length . filter isPellet . snd . unzip
    where isPellet x = x == '.' || x == '*'

readPosition :: IndexedMaze -> Char -> Either String Point
-- ^Read the row and column of the first instance of a character from
-- an IndexedMaze string.
readPosition xs x =
    case find ( (== x) . snd )  xs of
         Nothing     -> Left $ "Cannot find '" ++ [x] ++ "' in maze"
         Just (p, _) -> Right p

---------------------------------------------------------------------
-- Loading the player from the IndexedMaze.

loadPacMan :: IndexedMaze -> Either String PacMan
-- ^Read and initialize the player according to the IndexedMaze.
loadPacMan xs = do
    pos    <- readPosition xs 'P'
    return PacMan { _pdir   = West
                  , _ppos   = pos
                  , _pstrt  = (pos, West)
                  , _ptlast = 0
                  }

---------------------------------------------------------------------
-- Loading the ghosts from the IndexedMaze.

loadGhost :: IndexedMaze -> Char -> Either String Ghost
-- ^Read and intialize a ghost according to the IndexedMaze.
loadGhost xs c = do
    pos    <- readPosition xs c
    (n, d) <- readGhost c
    return Ghost { _gname     = n
                 , _gdir      = d
                 , _gpos      = pos
                 , _gstrt     = (pos, d)
                 , _gstate    = Normal
                 , _gtlast    = 0
                 , _gpathback = []
                 }

readGhost :: Char -> Either String (GhostName, Direction)
-- ^Helper function for initializing each ghost by name given its
-- ascii representation in a MazeString.
readGhost 'p' = Right ( Pinky,  East  )
readGhost 'b' = Right ( Blinky, West  )
readGhost 'i' = Right ( Inky,   West  )
readGhost 'c' = Right ( Clyde,  North )
readGhost x   = Left $ "Character '" ++ [x] ++ "' not recognized as ghost"

---------------------------------------------------------------------
-- Loading the fruit from the IndexedMaze.
-- Fruit loading has the following random components:
-- 1. The name of the fruit, or no fruit at all, which also depends
--    on the level.
-- 2. The position of the fruit, which can be any position marked
--    with an '?' in the MazeString.
-- 3. The delay time before the fruit appears.
-- The duration of time that a fruit can be captured is not random.

loadFruit :: StdGen -> Int -> IndexedMaze -> Either String (Maybe Fruit, StdGen)
-- ^This is the entry function. It returns a Nothing value for the
-- fruit if no fruit is to appear in the current level.
loadFruit r0 lvl xs = case getFruit r0 lvl xs of
                           Nothing      -> Right (Nothing, r0)
                           Just (f, r1) -> Right (Just f, r1)

getFruit :: StdGen -> Int -> IndexedMaze -> Maybe (Fruit, StdGen)
-- ^This is the helper function that actually loads the fruit.
getFruit r0 lvl xs = do
    (p,  r1) <- getFruitPosition r0 xs
    (fn, r2) <- getFruitName r1 lvl
    let (t0, r3) = getFruitDelay r2
        dt       = fruitDuration fn
    return ( Fruit fn dt t0 p, r3 )

getFruitPosition :: StdGen -> IndexedMaze -> Maybe (Point, StdGen)
-- ^Draw a random position for the fruit selecting from all positions
-- in the IndexedMaze that correspond to a '?' character.
getFruitPosition r0 xs
    | null ps   = Nothing
    | otherwise = Just ( ps !! k, r1 )
    where ps     = [ p | (p, x) <- xs, x == '?' ]
          (k,r1) = randomR (0, length ps - 1) r0

getFruitName :: StdGen -> Int -> Maybe (FruitName, StdGen)
-- ^Draw which fruit will appear in the level or whether no fruit
-- will appear at all (10% chance). The probabilities are inversely
-- proportional to points each fruit is worth.
getFruitName r0 lvl
    | k < 480 && lvl > 0 = Just ( Cherry,     r1 )
    | k < 640 && lvl > 1 = Just ( Strawberry, r1 )
    | k < 736 && lvl > 2 = Just ( Orange,     r1 )
    | k < 805 && lvl > 3 = Just ( Apple,      r1 )
    | k < 843 && lvl > 4 = Just ( Melon,      r1 )
    | k < 877 && lvl > 5 = Just ( Galaxian,   r1 )
    | k < 893 && lvl > 6 = Just ( Bell,       r1 )
    | k < 900 && lvl > 7 = Just ( Key,        r1 )
    | otherwise = Nothing
    where (k, r1) = randomR (0, 999 :: Int) r0

getFruitDelay :: StdGen -> (Time, StdGen)
-- ^Draw the time delay befor the fruit will appear in the level.
getFruitDelay = randomR (tmin, tmax)
    where tmin = toMicroSeconds 5
          tmax = toMicroSeconds 25

---------------------------------------------------------------------
-- Loading the actual maze.
-- Only the fixed maze tiles such as walls, pellets, warps and
-- oneways are loaded here. The player, ghosts and fruit are managed
-- and loaded separately, and the final maze with all tiles in place
-- is only generated right before rendering it to the screen.

loadMaze :: IndexedMaze -> Either String Maze
-- ^Entry function for generating the maze.
loadMaze [] = Left "No maze string provided."
loadMaze xs = M.fromList nr nc <$> mapM (readTile xs) xs
    where (nr,nc) = getDims xs

readTile :: IndexedMaze -> (Point, Char) -> Either String Tile
-- ^Convert ascii characters to fixed maze tiles. Everything else in
-- the IndexedMaze is interpretted as an empty tile.
readTile _  (_, '.') = Right Pellet
readTile _  (_, '*') = Right PwrPellet
readTile xs (p, 'w') = resolveWarp xs p
readTile _  (_, '^') = Right . OneWay $ North
readTile _  (_, 'v') = Right . OneWay $ South
readTile _  (_, '<') = Right . OneWay $ West
readTile _  (_, '>') = Right . OneWay $ East
readTile xs (p, '|') = Right . resolveWall xs p $ '|'
readTile xs (p, '=') = Right . resolveWall xs p $ '='
readTile _  _        = Right Empty

resolveWarp :: IndexedMaze -> Point -> Either String Tile
-- ^Setup warps for the maze. Note that only one pair of warps is
-- allowed in each maze that warps must always be paired.
resolveWarp xs (r,c)
    | r == 1    = Warp North <$> wLoc
    | c == 1    = Warp West  <$> wLoc
    | r == nr   = Warp South <$> wLoc
    | c == nc   = Warp East  <$> wLoc
    | otherwise = Left "Incorrect placement of warp tile"
    where (nr, nc) = getDims xs
          wLoc = case filter ( \ (p,x) -> x == 'w' && p /= (r,c) ) xs of
                      []        -> Left "Cannot find matching warp tile"
                      w:[]      -> Right . fst $ w
                      otherwise -> Left "Too many warp tiles"

isWallChar :: Char -> Bool
-- ^Defines what is a valid ascii representation of a wall character.
-- '|' denotes a vertical wall character and '=' denotes a horizontal
-- wall character.
isWallChar x = x == '|' || x == '='

resolveWall :: IndexedMaze -> Point -> Char -> Tile
-- ^Resolve how ascii characters representing walls should be linked.
resolveWall xs (r,c) x
    | nw && sw && ww && ew = Wall "╬"
    | nw && sw && ww       = Wall "╣"
    | nw && ww && ew       = Wall "╩"
    | nw && sw && ew       = Wall "╠"
    | sw && ww && ew       = Wall "╦"
    | nw && ww             = Wall "╝"
    | nw && ew             = Wall "╚"
    | sw && ww             = Wall "╗"
    | sw && ew             = Wall "╔"
    | sw || nw             = Wall "║"
    | otherwise            = Wall "═"
    where nw  = verticalLink x   . lookup (r-1, c) $ xs
          sw  = verticalLink x   . lookup (r+1, c) $ xs
          ww  = horizontalLink x . lookup (r, c-1) $ xs
          ew  = horizontalLink x . lookup (r, c+1) $ xs

verticalLink :: Char -> Maybe Char -> Bool
-- ^Is a character a wall character and linked above or below to
-- another wall character that may not exist. Stacked wall characters
-- running parallel horizontally should not be linked.
verticalLink _   Nothing    = False
verticalLink '|' (Just '|') = True
verticalLink x   (Just y  ) = isWallChar x && isWallChar y && x /= y

horizontalLink :: Char -> Maybe Char -> Bool
-- ^Is a character a wall character and linked left or right to
-- another wall character that may not exist. Side-by-side wall
-- characters running parallel vertically should not be lined.
horizontalLink _   Nothing    = False
horizontalLink '=' (Just '=') = True
horizontalLink x   (Just y  ) = isWallChar x && isWallChar y && x /= y

-- =============================================================== --
-- Working with strings encoding high score information

showHighScore :: HighScore -> String
-- ^Converts a high score value to string for saving. This replaces
-- all spaces with underscores and appends a new line character.
showHighScore ("", score  ) = showHighScore ("_", score)
showHighScore (name, score) = name' ++ " " ++ show score ++ "\n"
    where name' = intercalate "_" . words $ name

readHighScores :: Either String String -> [HighScore]
-- ^Read high scores from a string and convert to a list of high
-- score values. If no high scores are available (i.e., a Left value
-- is provided as the argument), then an empty list is generated.
-- High scores are read as lines terminated by '\n' with two strings
-- separated by whitespace. The first is the name and the second is
-- the score. Underscores in the name are converted to spaces. If the
-- is not properly formatted or cannot be read, it is excluded from
-- the list of generated high scores.
readHighScores (Left _  ) = []
readHighScores (Right xs) = maybe [] id . mapM (go . words) . lines $ xs
    where deUnder ys = [ if y == '_' then ' ' else y | y <- ys ]
          go ws | length ws /= 2 = Nothing
                | otherwise      = case readMaybe (ws !! 1) :: Maybe Score of
                                        Nothing -> Nothing
                                        Just x  -> Just (deUnder . head $ ws, x)

-- =============================================================== --
-- Command line parsing and options handling

-- Exported

getOptions :: [String] -> Either String Options
-- ^Parse command line arguments into Right Options record or return
-- an error message as the Left value.
getOptions args =
    let defaults = Options { _firstlevel = 1
                           , _firstmaze  = Nothing
                           , _info       = Nothing
                           , _terminal   = "xterm-256color" }
    in  case O.getOpt O.Permute optionsHub args of
             (xs, _, []) -> let opts = foldl' ( flip ($) ) defaults $ xs
                            in  maybe (Right opts) Left $ opts ^. T.info
             (_, _, es ) -> Left . concat $ es

-- Unexported

readFirstLevel :: String -> Int
-- ^Read a string as level value, and if not possible, then just
-- default to level 1.
readFirstLevel = maybe 1 id . readMaybe

optionsHub :: [ O.OptDescr (Options -> Options) ]
-- ^Used by GetOpt.getOpt to parse command line options. Contains
-- handlers for all possible command line options.
optionsHub =
    [ O.Option ['h'] ["help"]
          ( O.NoArg ( set T.info (Just R.help) ) )
          R.helpUsage
    , O.Option ['v'] ["version"]
          ( O.NoArg ( set T.info (Just R.version) ) )
          R.versionUsage
    , O.Option ['t'] ["terminal"]
          ( O.ReqArg ( set T.terminal ) "TERMINAL-IDENTIFIER" )
          R.terminalUsage
    , O.Option ['m'] ["maze"]
          ( O.ReqArg ( set T.firstmaze . Just ) "PATH-TO-MAZE-FILE" )
          R.mazeUsage
    , O.Option ['b'] ["backdoor"]
          ( O.ReqArg ( set T.firstlevel . readFirstLevel ) "LEVEL-NUMBER" )
          "" -- Allows starting at any level, so don't tell the user about it.
    ]
