module Main

-- An index written as a sum: `n + m` on `Nat` is base's `plus`, which the
-- index language reads as a sum of its parts, so a vector whose length
-- adds two lengths keeps that length in its type, at known lengths (where
-- the sum is the number they add to) and at a length read at run time.

import Prelude
import Data.Vect

joined : Vect n Int -> Vect m Int -> Vect (n + m) Int
joined xs ys = xs ++ ys

main : IO ()
main = do
  c <- getChar
  let k = the Nat (cast (ord c - 48))
  printLn (toList (joined [1, 2] [3]))
  printLn (toList (joined (replicate k 4) [5, 6]))
  printLn (toList (joined [7] (replicate k 8)))
