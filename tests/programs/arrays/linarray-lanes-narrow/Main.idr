module Main

-- Loops over an array's index space whose bodies compute on the index:
-- the cubes (i + 1)^3 as Ints, 1 / (i + 1)^2 as Doubles, and the squares
-- (i + k)^2 at an offset k read at run time, each summed in index order.
-- The compiler vectorizes each loop and gives it a version whose integer
-- lanes compute in 32 bits while every size and offset it reads from
-- outside is at most a bound its body decides (2^10 for the cubes, 2^15
-- for the inverse squares and 2^14 for the squares, as the analysis bounds
-- them), and runs it on 64-bit lanes otherwise; a negative offset, read
-- unsigned, is above every bound. The same program is the fixture
-- linarray-lanes-narrow, with n below every bound, and linarray-lanes-wide,
-- with n above them all; each sums the squares at a positive and at a
-- negative offset, and neither n is a multiple of the lanes, so that the
-- last tile runs too. Either way the numbers are those of 64-bit lanes.

import Prelude
import Data.List
import Linear.Notation
import Linear.Array

cubes : Int -> Array Int
cubes n = generate n (\i => (i + 1) * (i + 1) * (i + 1))

inverseSquares : Int -> Array Double
inverseSquares n = generate n (\i => 1.0 / cast ((i + 1) * (i + 1)))

squares : Int -> Int -> Array Int
squares k n = generate n (\i => (i + k) * (i + k))

-- x with d decimals, for a non-negative x.
fixed : Nat -> Double -> String
fixed d x =
  let scale = cast {to = Int} (pow 10.0 (cast d))
      s = cast {to = Int} (x * cast scale + 0.5)
      frac = show (s `mod` scale)
  in show (s `div` scale) ++ "." ++ pack (replicate (minus d (length frac)) '0') ++ frac

-- An Int from stdin: digits after an optional '-', ended by any other
-- character.
readInt : IO Int
readInt = do
  c <- getChar
  if c == '-' then negate <$> go 0 else if isDigit c then go (cast (ord c - 48)) else pure 0
  where
    go : Int -> IO Int
    go acc = do
      c <- getChar
      if isDigit c then go (acc * 10 + cast (ord c - 48)) else pure acc

main : IO ()
main = do
  n <- readInt
  k <- readInt
  m <- readInt
  printLn (freeze (cubes n) Linear.Array.sum)
  printLn (freeze (cubes n) (\a => iread a (n - 1)))
  putStrLn (fixed 9 (freeze (inverseSquares n) Linear.Array.sum))
  printLn (freeze (squares k n) Linear.Array.sum)
  printLn (freeze (squares m n) Linear.Array.sum)
