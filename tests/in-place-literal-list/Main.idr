module Main

import Prelude
import Linear.Notation
import Linear.List

-- A list written as a literal and passed straight to a function that
-- rebuilds it: its cells are built where the literal is evaluated, never
-- folded into static data, since a value of a linear list takes a fresh
-- identity where it is made; so bump is passed it exclusive and rebuilds
-- it in place, writing no memory the program did not allocate.

bump : LList (!* Int) -@ LList (!* Int)
bump [] = []
bump (MkBang x :: xs) = MkBang (x + 1) :: bump xs

sumL : Int -> LList (!* Int) -@ !* Int
sumL acc [] = MkBang acc
sumL acc (MkBang x :: xs) = sumL (acc + x) xs

main : IO ()
main = do
  c <- getChar
  let MkBang s = sumL 0 (if c == 'a' then bump [MkBang 1, MkBang 2] else bump [])
  printLn s
