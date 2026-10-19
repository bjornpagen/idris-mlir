module Main

-- The length of the accumulator is a runtime argument that the rest of
-- build's type mentions only as the index of a vector, which exists at
-- compile time only. So one instance of build serves every call, however
-- deep each recursive call builds the length (`S n`).

import Prelude
import Data.Vect

vsum : Vect n Int -> Int
vsum [] = 0
vsum (x :: xs) = x + vsum xs

build : (n : Nat) -> Vect n Int -> Int -> Int
build n acc 0 = vsum acc
build n acc k = build (S n) (k :: acc) (k - 1)

main : IO ()
main = do
  line <- getLine
  printLn (build 0 [] (cast line))
