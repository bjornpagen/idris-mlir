module Main

import Prelude
import Prog

-- The size and the index, a line each.
main : IO ()
main = do
  n <- getLine
  i <- getLine
  printLn !(readAt (cast n) (cast i))
