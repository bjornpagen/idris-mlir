module Main

-- A stream consumer the Prelude declares covering: `takeBefore` forces the
-- elements of an infinite Stream up to the first its predicate holds of,
-- 64, and ends there.

import Prelude

main : IO ()
main = printLn (sum (takeBefore (> 40) (countFrom (the Int 1) (* 2))))
