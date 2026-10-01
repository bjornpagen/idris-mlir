-- Maximum subarray (LeetCode 53), Kadane's pass over a linear list of
-- pseudo-random values: the list is consumed, each cell freed as it is read.
module Main

import Prelude
import Data.Linear.Notation
import Data.Linear.LList

-- A list of n values in [-50, 49] from a linear congruential generator.
build : Int -> Int -> LList (!* Int) -@ LList (!* Int)
build n seed acc =
  if n <= 0 then acc
  else let seed' = (seed * 1103515245 + 12345) `mod` 2147483648
       in build (n - 1) seed' (MkBang ((seed' `div` 65536) `mod` 100 - 50) :: acc)

kadane : (1 xs : LList (!* Int)) -> Int -> Int -> Int
kadane [] _ best = best
kadane (MkBang x :: xs) here best =
  let here' = max x (here + x)
  in kadane xs here' (max best here')

readInt : IO Int
readInt = go 0
  where
    go : Int -> IO Int
    go acc = do
      c <- getChar
      if isDigit c then go (acc * 10 + cast (ord c - 48)) else pure acc

main : IO ()
main = do
  n <- readInt
  printLn (kadane (build (n `div` 5000) 1 []) 0 (-1000000))
  printLn (kadane (build n 7 []) 0 (-1000000))
