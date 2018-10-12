module Model.Utilities
    ( tickPeriod
    , playerWaitTime
    , ghostWaitTime
    , edibleGhostWaitTime
    , messageTime
    , powerDuration
    , powerTimeLeft
    , playerScore
    , isWall
    , noWalls
    , moveFrom
    , revDirection
    , pathBetween
    ) where

import qualified Data.Matrix    as M
import qualified Model.Types    as T
import qualified Data.Vector    as V
import Data.Matrix                      ( (!)            )
import Data.List                        ( foldl'         )
import Lens.Micro                       ( (^.)           )
import Model.Types                      ( Tile      (..)
                                        , Time      (..)
                                        , Game      (..)
                                        , Maze      (..)
                                        , Point     (..)
                                        , Status    (..)
                                        , Direction (..) )

---------------------------------------------------------------------
-- Default constants

tickPeriod :: Time
-- ^Time between clock ticks.
tickPeriod = 225000 -- microseconds

playerWaitTime :: Time
-- ^Wait time for player between moves.
playerWaitTime = tickPeriod

ghostWaitTime :: Time
-- ^Wait time for normal ghosts between moves.
ghostWaitTime = tickPeriod

edibleGhostWaitTime :: Time
-- ^Wait time for edible ghosts between moves.
edibleGhostWaitTime = 2 * ghostWaitTime

messageTime :: Time
-- ^Length of time messages are displayed.
messageTime = 3000000 -- microseconds

powerDuration :: Time
-- ^Length of time ghosts remain edible after eating a power pellet.
powerDuration = 7500000 -- microseconds

---------------------------------------------------------------------
-- Game state query utilities

powerTimeLeft :: Game -> Time
-- ^Query how much time is left for the curret powered state (i.e.,
-- after the player has eaten a power pellet). If the game state is
-- not powered, evaluate to 0.
powerTimeLeft g
    | dt > 0    = dt
    | otherwise = 0
    where dt = case g ^. T.status of
                    PwrRunning t0 -> g ^. T.pwrtime - ( g ^. T.time - t0 )
                    otherwise     -> 0

playerScore :: Game -> Int
-- ^Compute the current score based on the game state.
playerScore gm = pel + ppel + gst + frt
    where pel  = 10 * gm ^. T.items . T.pellets
          ppel = 50 * gm ^. T.items . T.ppellets
          gst  = gm ^. T.items . T.gstscore
          frt  = foldl' ( \ s (_,fs) -> s + fs ) 0 $ gm ^. T.items . T.fruits

---------------------------------------------------------------------
-- Determining tile subtypes

isWall :: Tile -> Bool
-- ^Evaluate whether a tile is a wall tile.
isWall (Wall _) = True
isWall _        = False

noWalls :: Int -> Int -> V.Vector Tile -> Bool
-- ^Determine if there are no wall tiles between two elements in a
-- vector of tiles.
noWalls x y ts
    | x < y     = not . V.any isWall . V.slice x d $ ts
    | x > y     = not . V.any isWall . V.slice y d $ ts
    | otherwise = False
    where d = abs $ x - y

---------------------------------------------------------------------
-- Utilities for moving player and ghosts

moveFrom :: Maze -> Point -> Direction -> Point
-- ^Get next maze position based on current position and direction.
moveFrom m p d = let go (x0,y0) (x1,y1) = (x0 + x1, y0 + y1)
                     nxt                = go p . dirToShift $ d
                 in  case m ! p of
                          Warp wd wp -> if wd == d then wp else nxt
                          OneWay owd -> if owd == d then nxt else p
                          otherwise  -> nxt

revDirection :: Direction -> Direction
revDirection North = South
revDirection South = North
revDirection West  = East
revDirection East  = West

-- unexported

dirToShift :: Direction -> Point
-- ^Maps directions to single-tick displacements.
dirToShift West  = (0,-1)
dirToShift East  = (0, 1)
dirToShift North = (-1,0)
dirToShift South = (1, 0)

---------------------------------------------------------------------
-- Path-finding

pathBetween :: Maze -> Point -> Point -> [Point]
-- ^Return a list of points that connect p0 and p1 in the maze m.
-- The algorithm works by adding the inital point p0 to the list. All
-- points connected to p0 are then added to the end of the list, and
-- the next point is considered adding all points connected to it to
-- the end of the list that are not already in the list. This repeats
-- until the final point p1 is reached and added as the last element
-- in the list. Thus, the last element of the list (p1) is connected
-- to the first element (p0) via a sequence of points in between.
-- A connected sublist from the last to first is then a path between.
pathBetween m p0 p1
    | p0 == p1  = []
    | otherwise = go . reverse . getPaths m p1 [] $ [p0]
    where go []     = []
          go (x:xs) = go ( dropWhile (not . connected x ) xs ) ++ [x]

-- unexported

getPaths :: Maze -> Point -> [Point] -> [Point] -> [Point]
getPaths m p ys (x:xs)
    | p == x     = ys ++ [x]
    | elem p nxt = ys' ++ [p]
    | otherwise  = getPaths m p ys' (xs ++ nxt)
    where ys' = ys ++ [x]
          nxt = getNxtPoints m (ys ++ xs) x

getNxtPoints :: Maze -> [Point] -> Point -> [Point]
getNxtPoints m xs = filter ( not . flip elem xs ) . go
    where go  (r,c) = filter chk [ (r,c-1), (r,c+1), (r-1,c), (r+1,c) ]
          chk (r,c) = case M.safeGet r c m of
                           Nothing -> False
                           Just t  -> not . isWall $ t

connected :: Point -> Point -> Bool
connected (r1,c1) (r2,c2) = dr + dc < 2
    where dr = abs $ r1 - r2
          dc = abs $ c1 - c2
