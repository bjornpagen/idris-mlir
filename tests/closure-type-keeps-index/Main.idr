module Main

-- A function of a vector at any length, written point-free: its value is
-- the closure `(.)` returns, at the length its caller names. `(.)` is
-- keyed by its type arguments with that length left out, and takes it as
-- an index parameter of its own, which each call gives, so the closure's
-- type keeps the length at a known length and at one read at run time.

import Prelude
import Data.Vect

summed : Vect n Int -> Int
summed = sum . toList

main : IO ()
main = do
  c <- getChar
  let k = the Nat (cast (ord c - 48))
  printLn (summed [1, 2, 3])
  printLn (summed (replicate k 5))
