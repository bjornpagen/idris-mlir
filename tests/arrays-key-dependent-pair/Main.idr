module Main

-- A dependent pair of a length and a vector of it: the shape stands under
-- the family's lambda (`\n => Vector n Int`), and the key of the pair holds
-- the family with the shape cut to its form, one axis.

import Prelude
import Array

ramp : Nat -> (n ** Vector n Int)
ramp k = (k ** tabulate [<k] (\[<i] => cast (finToNat i)))

main : IO ()
main = do
  line <- getLine
  let (n ** v) = ramp (cast line)
  printLn (n, sum v)
