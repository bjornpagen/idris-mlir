module Main

import Prelude
import Prog

-- Two Doubles, a line each, and their quotient cast to an Int. The guard
-- fails on NaN and on either infinity, and on no finite value: a finite one
-- is truncated toward zero, modulo 2^64.
partial
main : IO ()
main = do
  x <- getLine
  y <- getLine
  printLn (nearest (cast x) (cast y))
