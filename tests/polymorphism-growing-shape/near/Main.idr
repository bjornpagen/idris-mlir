module Main

import Prelude

-- The refused program with n passed back unchanged: grow has the one
-- instance its call from main needs, and replaces the tuple's only Int at
-- each round, so its value is the last count, 1, or the start for 0.

Ints : Nat -> Type
Ints Z = Int
Ints (S k) = (Int, Ints k)

first : (n : Nat) -> Ints n -> Int
first Z x = x
first (S k) (x, _) = x

grow : (n : Nat) -> Ints n -> Int -> Int
grow n acc 0 = first n acc
grow Z acc k = grow Z k (k - 1)
grow (S m) (_, rest) k = grow (S m) (k, rest) (k - 1)

main : IO ()
main = do
  line <- getLine
  printLn (grow Z 0 (cast line))
