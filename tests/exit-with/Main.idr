module Main

-- A line written, then exitWith (ExitFailure 3): the line reaches stdout,
-- the status is 3, and the exit writes no count of live cells, since it
-- ends the process where it stands.

import Prelude
import System

main : IO ()
main = do
  putStrLn "before the exit"
  exitWith (ExitFailure 3)
