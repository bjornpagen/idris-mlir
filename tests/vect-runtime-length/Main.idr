module Main

-- The length of a vector is a runtime argument that the rest of the
-- function's type mentions only as the vector's index, which exists at
-- compile time only. So one instance of each function serves every call,
-- however deep each recursive call builds the length (`S n`): whether the
-- recursion ends on a counter (count) or on a match on the length three
-- constructors deep (upTo3).

import Prelude
import Data.Vect

vsum : Vect n Int -> Int
vsum [] = 0
vsum (x :: xs) = x + vsum xs

count : (n : Nat) -> Vect n Int -> Int -> Int
count n acc 0 = vsum acc
count n acc k = count (S n) (k :: acc) (k - 1)

upTo3 : (n : Nat) -> Vect n Int -> Int
upTo3 (S (S (S _))) acc = vsum acc
upTo3 n acc = upTo3 (S n) (1 :: acc)

main : IO ()
main = do
  line <- getLine
  let n = the Int (cast line)
  printLn (count 0 [] n)
  let k = the Nat (cast n)
  printLn (upTo3 k (replicate k 7))
  printLn (upTo3 Z [])
