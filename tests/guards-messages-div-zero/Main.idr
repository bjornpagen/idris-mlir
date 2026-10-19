module Main

import Prelude
import Prog

-- The dividend and the divisor, a line each. The guard fails at a divisor
-- of 0, whatever the dividend, and nowhere else: the quotient is
-- Euclidean (its remainder is never negative), and the least Int divided
-- by -1 is itself, wrapped.
partial
main : IO ()
main = do
  x <- getLine
  y <- getLine
  printLn (quotient (cast x) (cast y))
