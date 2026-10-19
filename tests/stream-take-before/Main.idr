module Main

-- A stream consumer the Prelude declares covering: `takeBefore` forces the
-- elements of an infinite Stream, the powers of two, up to the first its
-- predicate holds of, the first past a bound read at run time, and ends
-- there: before 1 when the bound is 0, before 2 when it is 1, before 64
-- when it is 40, before 128 when it is 64 (equal is not past), and before
-- 2^62 when it is 2^61.

import Prelude

main : IO ()
main = do
  line <- getLine
  let bound = the Int (cast line)
  printLn (sum (takeBefore (> bound) (countFrom (the Int 1) (* 2))))
