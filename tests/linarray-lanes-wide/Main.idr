module Main

-- Loops over an array's index space whose bodies compute on the index:
-- the cubes (i + 1)^3 as Ints, 1 / (i + 1)^2 as Doubles, and the squares
-- (i + k)^2 at an offset k read at run time, each summed in index order.
-- The compiler vectorizes each loop and gives it a version whose integer
-- lanes compute in 32 bits while every size and offset it reads from
-- outside is at most a bound its body decides, and runs it on 64-bit
-- lanes otherwise; a negative offset, read unsigned, is above every bound.
-- The loops run twice, with n below every bound and with n above them all;
-- each run sums the squares at a positive and at a negative offset, and
-- neither n is a multiple of the lanes, so that the last tile runs too.
-- Either way the numbers are those of 64-bit lanes.

import Prelude
import Data.List
import Array

-- A position as the Int the program computes with.
at : Fin n -> Int
at i = cast (finToNat i)

cubes : (n : Nat) -> Vector n Int
cubes n = tabulate [<n] (\[<i] => (at i + 1) * (at i + 1) * (at i + 1))

inverseSquares : (n : Nat) -> Vector n Double
inverseSquares n = tabulate [<n] (\[<i] => 1.0 / cast ((at i + 1) * (at i + 1)))

squares : Int -> (n : Nat) -> Vector n Int
squares k n = tabulate [<n] (\[<i] => (at i + k) * (at i + k))

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

-- Each loop on n elements, with the offsets k and m.
runAll : Int -> Int -> Int -> IO ()
runAll count k m = do
  let n = cast {to = Nat} count
  printLn (sum (cubes n))
  printLn (fromMaybe 0 (cubes n !? [<natToInteger n - 1]))
  putStrLn (fixed 9 (sum (inverseSquares n)))
  printLn (sum (squares k n))
  printLn (sum (squares m n))

-- Two runs, each of a size and two offsets read from stdin.
main : IO ()
main = do
  narrow <- readInt
  k <- readInt
  m <- readInt
  runAll narrow k m
  wide <- readInt
  k' <- readInt
  m' <- readInt
  runAll wide k' m'
