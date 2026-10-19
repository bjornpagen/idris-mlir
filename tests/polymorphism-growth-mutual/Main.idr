-- expect: polymorphism, line 24
-- message: (Prelude.Types.S (Prelude.Types.S n))
module Main

import Prelude

-- Pad n is Int once n is known to its last constructor, so a function over
-- it takes all of n's shape in each instance. up passes down its argument
-- two constructors deeper, and down takes one off before it calls up
-- again: each round grows the argument by one, and the instances the run
-- needs are as many as its input says. near/ grows it by one constructor
-- and shrinks it by one, so the instances are up at Z and down at Z and
-- S Z, however many rounds the input asks for.

Pad : Nat -> Type
Pad Z = Int
Pad (S k) = Pad k

value : (n : Nat) -> Pad n -> Int
value Z x = x
value (S k) x = value k x

mutual
  up : (n : Nat) -> Pad n -> Int -> Int -> Int
  up n x 0 acc = value n x + acc
  up n x k acc = down (S (S n)) x (k - 1) (acc + 10)

  down : (n : Nat) -> Pad n -> Int -> Int -> Int
  down Z x k acc = up Z x k acc
  down (S m) x k acc = up m x k (acc + 1)

main : IO ()
main = do
  line <- getLine
  printLn (down Z 5 (cast line) 0)
