-- expect: polymorphism, line 19
-- message: which its recursion builds deeper at each call
module Main

import Prelude

-- Ints n is a tuple of n + 1 Ints: its representation needs all of n, and
-- grow builds n one constructor deeper at each call, so each instance of
-- grow would need another.

Ints : Nat -> Type
Ints Z = Int
Ints (S k) = (Int, Ints k)

first : (n : Nat) -> Ints n -> Int
first Z x = x
first (S k) (x, _) = x

grow : (n : Nat) -> Ints n -> Int -> Int
grow n acc 0 = first n acc
grow n acc k = grow (S n) (k, acc) (k - 1)

main : IO ()
main = do
  line <- getLine
  printLn (grow Z 0 (cast line))
