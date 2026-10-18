-- expect: polymorphism, line 22
-- message: growing it by 1 each round through
module Main

import Prelude

-- Pad n is Int once n is known to its last constructor, so a function over
-- it takes all of n's shape in each instance. up passes down its argument
-- two constructors deeper, and down takes one off before it calls up
-- again: each round grows the argument by one, and the instances the run
-- needs are as many as its input says.

Pad : Nat -> Type
Pad Z = Int
Pad (S k) = Pad k

value : (n : Nat) -> Pad n -> Int
value Z x = x
value (S k) x = value k x

mutual
  up : (n : Nat) -> Pad n -> Int -> Int
  up n x 0 = value n x
  up n x k = down (S (S n)) x (k - 1)

  down : (n : Nat) -> Pad n -> Int -> Int
  down Z x k = up Z x k
  down (S m) x k = up m x k

main : IO ()
main = do
  line <- getLine
  printLn (up Z 7 (cast line))
