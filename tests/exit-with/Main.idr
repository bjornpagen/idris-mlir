module Main

-- A line written, then exitWith (ExitFailure n), n the digit on stdin (207
-- at the end of input, getChar's 255 less '0'): the line reaches stdout and
-- the status is n. A status no parent can read (below 0, as `/` gives) is a
-- crash at the exit's site, its line before it flushed. On 0 the program
-- does not exit, and main returns.

import Prelude
import Data.So
import System

main : IO ()
main = do
  c <- getChar
  let n = ord c - ord '0'
  putStrLn "before the exit"
  case choose (n == 0) of
    Left _ => putStrLn "no exit"
    Right _ => exitWith (ExitFailure n)
