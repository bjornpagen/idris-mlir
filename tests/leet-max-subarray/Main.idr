-- Maximum subarray (LeetCode 53), Kadane's pass over a linear list of
-- pseudo-random values: the list is consumed, each cell freed as it is read.
-- On the short list a brute force over every contiguous part, of the same
-- values as a plain list, is a second implementation that must agree; an
-- all-negative list's answer is its largest element, and the empty list's
-- is the starting best.
module Main

import Prelude
import Linear.Notation
import Linear.List

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

-- The same values as a plain list.
plain : Int -> Int -> List Int -> List Int
plain n seed acc =
  if n <= 0 then acc
  else let seed' = (seed * 1103515245 + 12345) `mod` 2147483648
       in plain (n - 1) seed' (((seed' `div` 65536) `mod` 100 - 50) :: acc)

-- The largest sum of the parts that start at the head, from a running sum.
fromHead : List Int -> Int -> Int -> Int
fromHead [] _ best = best
fromHead (x :: xs) run best = fromHead xs (run + x) (max best (run + x))

-- The largest sum of every contiguous part, each start in turn.
brute : List Int -> Int -> Int
brute [] best = best
brute (x :: xs) best = brute xs (max best (fromHead (x :: xs) 0 (-1000000)))

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
  printLn (brute (plain (n `div` 5000) 1 []) (-1000000))
  printLn (kadane (MkBang (-3) :: MkBang (-1) :: MkBang (-2) :: []) 0 (-1000000))
  printLn (kadane (build n 7 []) 0 (-1000000))
