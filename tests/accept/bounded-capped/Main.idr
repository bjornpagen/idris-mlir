module Main

import Prelude

-- Res looks at two constructors of its argument: an Integer from two up,
-- a String below. count steps from zero to one to two, and then builds
-- its argument one constructor deeper at each call, below what Res looks
-- at, so every call from two up shares one instance: count has three.

Res : Nat -> Type
Res (S (S _)) = Integer
Res _ = String

count : (n : Nat) -> Res n -> Int -> Integer
count Z s k = count (S Z) s k
count (S Z) s k = count (S (S Z)) (cast (length s)) k
count (S (S m)) r 0 = r + cast m
count (S (S m)) r k = count (S (S (S m))) (r + 1) (k - 1)

main : IO ()
main = do
  printLn (count Z "four" 3)
  printLn (count (S (S Z)) 10 2)
