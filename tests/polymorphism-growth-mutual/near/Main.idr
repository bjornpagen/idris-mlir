module Main

import Prelude

-- The refused program with up passing down its argument one constructor
-- deeper: down takes it off again, so the instances are up at Z and down
-- at Z and S Z, however many rounds the input asks for. Each round adds
-- 10 in up and 1 in down, so k rounds from 5 make 5 + 11k.

Pad : Nat -> Type
Pad Z = Int
Pad (S k) = Pad k

value : (n : Nat) -> Pad n -> Int
value Z x = x
value (S k) x = value k x

mutual
  up : (n : Nat) -> Pad n -> Int -> Int -> Int
  up n x 0 acc = value n x + acc
  up n x k acc = down (S n) x (k - 1) (acc + 10)

  down : (n : Nat) -> Pad n -> Int -> Int -> Int
  down Z x k acc = up Z x k acc
  down (S m) x k acc = up m x k (acc + 1)

main : IO ()
main = do
  line <- getLine
  printLn (down Z 5 (cast line) 0)
