module Main

import Prelude
import Prog

-- The string is the line on stdin; the guard fails on the empty one alone,
-- and the head of any other is its first character, not its first byte.
partial
main : IO ()
main = do
  s <- getLine
  printLn (first s)
