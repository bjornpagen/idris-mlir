module Main

-- As vect-runtime-length-accumulator, with the recursion ended by a match
-- on the length three constructors deep rather than by a counter: the
-- length is still only an index of build's type, so one instance matches
-- every length at runtime.

import Prelude
import Data.Vect

vsum : Vect n Int -> Int
vsum [] = 0
vsum (x :: xs) = x + vsum xs

build : (n : Nat) -> Vect n Int -> Int
build (S (S (S _))) acc = vsum acc
build n acc = build (S n) (1 :: acc)

main : IO ()
main = do
  line <- getLine
  let k = the Nat (cast line)
  printLn (build k (replicate k 7))
  printLn (build Z [])
