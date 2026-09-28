-- expect: PROF-DATA-3 line 9
module Main

import Prelude

-- A range over Int is `takeUntil (>= 10) (countFrom 1 (+ 1))`, and the
-- Prelude declares `takeUntil` covering. Partial code is never evaluated at
-- compile time (SEM-EVAL-6), so the list would be built at runtime.
main : IO ()
main = do
  printLn (sum [the Int 1 .. 10])
