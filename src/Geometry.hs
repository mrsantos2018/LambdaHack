module Geometry
  ( Time, VDir(..), X, Y, Loc, Dir, toLoc, fromLoc, trLoc, zeroLoc
  , Area, towards, distance, dirDistSq, adjacent, surroundings, diagonal, shift
  , neg, moves, neighbors, fromTo, normalize, normalizeArea, grid, shiftXY
  ) where

import qualified Data.List as L
import Data.Binary

import Utils.Assert


-- Assorted

-- | Game time in turns. (Placement in module Geometry is not ideal.)
type Time = Int

-- | Vertical directions.
data VDir = Up | Down
  deriving (Eq, Ord, Show, Enum, Bounded)

type X = Int
type Y = Int

shiftXY :: (X, Y) -> (X, Y) -> (X, Y)
shiftXY (x0, y0) (x1, y1) = (x0 + x1, y0 + y1)

-- | Vectors of all unit moves, clockwise, starting north-west.
movesXY :: [(X, Y)]
movesXY = [(-1, -1), (0, -1), (1, -1), (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0)]


-- Loc

-- Loc is a positivie integer for speed and to enforce the use of wrappers
-- (we don't want newtype to avoid the trouble with using EnumMap
-- in place of IntMap, etc.). We do bounds check for the X size ASAP
-- and each subsequent array access performs a checlk, effectively for Y size.
-- After dungeon is generated (using (X, Y), not Loc), Locs are used
-- mainly as keys and not constructed often, so the performance will improve
-- due to smaller save files, IntMaps and cheaper array indexing,
-- including cheaper bounds check.
type Loc = Int

toLoc :: X -> (X, Y) -> Loc
toLoc lxsize (x, y) =
  assert (lxsize > x && x >= 0 && y >= 0 `blame` (lxsize, x, y)) $
  x + y * lxsize

fromLoc :: X -> Loc -> (X, Y)
fromLoc lxsize loc =
  assert (loc >= 0 `blame` (lxsize, loc)) $
  (loc `rem` lxsize, loc `quot` lxsize)

trLoc :: X -> Loc -> (X, Y) -> Loc
trLoc lxsize loc (dx, dy) =
  assert (loc >= 0 && res >= 0 `blame` (lxsize, loc, (dx, dy))) $
  res
   where res = loc + dx + dy * lxsize

zeroLoc :: Loc
zeroLoc = 0

-- | The distance between two points in the metric with diagonal moves.
distance :: X -> Loc -> Loc -> Int
distance lxsize loc0 loc1
  | (x0, y0) <- fromLoc lxsize loc0, (x1, y1) <- fromLoc lxsize loc1 =
  max (x1 - x0) (y1 - y0)

-- | Return whether two locations are adjacent on the map
-- (horizontally, vertically or diagonally). Currrently, a
-- position is also considered adjacent to itself.
adjacent :: X -> Loc -> Loc -> Bool
adjacent lxsize s t = distance lxsize s t <= 1

-- | Return the 8 surrounding locations of a given location.
surroundings :: X -> Y -> Loc -> [Loc]
surroundings lxsize lysize loc | (x, y) <- fromLoc lxsize loc =
  [ toLoc lxsize (x + dx, y + dy)
  | (dx, dy) <- movesXY,
    x + dx >= 0 && x + dx < lxsize &&
    y + dy >= 0 && y + dy < lysize ]


-- Dir, depends on Loc

-- Vectors of length 1 (in our metric), that is, geographical directions.
-- Implemented as an offset in the linear framebuffer indexed by Loc.
-- A newtype to prevent mixing up with Loc itself.
-- Level X size has to be > 1 for the @moves@ vectors to make sense.
newtype Dir = Dir Int deriving (Show, Eq)

instance Binary Dir where
  put (Dir dir) = put dir
  get = fmap Dir get

lenDir :: (X, Y) -> Int
lenDir (x, y) = max (abs x) (abs y)

toDir :: X -> (X, Y) -> Dir
toDir lxsize (x, y) =
  assert (lxsize > 1 && lenDir (x, y) == 1 `blame` (lxsize, (x, y))) $
  Dir $ x + y * lxsize

fromDir :: X -> Dir -> (X, Y)
fromDir lxsize (Dir dir) =
  assert (lenDir res == 1 && fst res + snd res * lxsize == dir
          `blame` (lxsize, dir, res)) $
  res
 where
   (x, y) = (dir `mod` lxsize, dir `div` lxsize)
   -- Pick the vector's canonical of length 1:
   res = if x > 1
         then (x - 80, y + 1)
         else (x, y)

-- | The squared euclidean distance between two directions.
dirDistSq :: X -> Dir -> Dir -> Int
dirDistSq lxsize dir0 dir1
  | (x0, y0) <- fromDir lxsize dir0, (x1, y1) <- fromDir lxsize dir1 =
  let square a = a * a
  in square (y1 - y0) + square (x1 - x0)

diagonal :: X -> Dir -> Bool
diagonal lxsize dir | (x, y) <- fromDir lxsize dir =
  x * y /= 0

-- | Invert a direction (vector).
neg :: Dir -> Dir
neg (Dir dir) = Dir (-dir)

-- | Directions of all unit moves, clockwise, starting north-west.
moves :: X -> [Dir]
moves lxsize = map (toDir lxsize) movesXY

-- | Move one square in the given direction.
-- Particularly simple in the linear representation.
shift :: Loc -> Dir -> Loc
shift loc (Dir dir) = loc + dir

-- | Given two distinct locations, determine the direction in which one should
-- move from the first in order to get closer to the second. Does not
-- pay attention to obstacles at all.
towards :: X -> Loc -> Loc -> Dir
towards lxsize loc0 loc1
  | (x0, y0) <- fromLoc lxsize loc0, (x1, y1) <- fromLoc lxsize loc1 =
  assert (loc0 /= loc1 `blame` (x0, y0)) $
  let dx = x1 - x0
      dy = y1 - y0
      angle :: Double
      angle = atan (fromIntegral dy / fromIntegral dx) / (pi / 2)
      dxy | angle <= -0.75 = (0, -1)
          | angle <= -0.25 = (1, -1)
          | angle <= 0.25  = (1, 0)
          | angle <= 0.75  = (1, 1)
          | angle <= 1.25  = (0, 1)
          | otherwise      = assert `failure` (lxsize, (x0, y0), (x1, y1))
  in if dx >= 0 then toDir lxsize dxy else neg (toDir lxsize dxy)


-- Area

type Area = (X, Y, X, Y)

neighbors :: Area ->        {- size limitation -}
             (X, Y) ->      {- location to find neighbors of -}
             [(X, Y)]
neighbors area xy =
  let cs = [ xy `shiftXY` (dx, dy)
           | dy <- [-1..1], dx <- [-1..1], (dx + dy) `mod` 2 == 1 ]
  in  L.filter (`inside` area) cs

inside :: (X, Y) -> Area -> Bool
inside (x, y) (x0, y0, x1, y1) =
  x1 >= x && x >= x0 && y1 >= y && y >= y0

fromTo :: (X, Y) -> (X, Y) -> [(X, Y)]
fromTo (x0, y0) (x1, y1) =
 let result
       | x0 == x1 = L.map (\ y -> (x0, y)) (fromTo1 y0 y1)
       | y0 == y1 = L.map (\ x -> (x, y0)) (fromTo1 x0 x1)
       | otherwise = assert `failure` ((x0, y0), (x1, y1))
 in result

fromTo1 :: Int -> Int -> [Int]
fromTo1 x0 x1
  | x0 <= x1  = [x0..x1]
  | otherwise = [x0,x0-1..x1]

normalize :: ((X, Y), (X, Y)) -> ((X, Y), (X, Y))
normalize (a, b) | a <= b    = (a, b)
                 | otherwise = (b, a)

normalizeArea :: Area -> Area
normalizeArea (x0, y0, x1, y1) = (min x0 x1, min y0 y1, max x0 x1, max y0 y1)

grid :: (X, Y) -> Area -> [((X, Y), Area)]
grid (nx, ny) (x0, y0, x1, y1) =
  let yd = y1 - y0
      xd = x1 - x0
  in [ ((x, y), (x0 + (xd * x `div` nx),
                 y0 + (yd * y `div` ny),
                 x0 + (xd * (x + 1) `div` nx - 1),
                 y0 + (yd * (y + 1) `div` ny - 1)))
     | x <- [0..nx-1], y <- [0..ny-1] ]
