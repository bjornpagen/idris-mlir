module Main

-- The process's arguments and environment, through base's System. The
-- harness passes no argument, so the arguments are the program's path
-- alone: their number is printed, never the path, which is where the
-- harness put the program. A variable the program sets reads back, twice,
-- each read a string the runtime keeps until the next environment
-- operation; a name the program unsets reads as Nothing. No value of the
-- host's environment is printed, and the program ends with no live cell.

import Prelude
import System

main : IO ()
main = do
  args <- getArgs
  printLn (length args)
  printLn !(setEnv "IDRIS_MLIR_T" "1" True)
  first <- getEnv "IDRIS_MLIR_T"
  second <- getEnv "IDRIS_MLIR_T"
  printLn (first, second)
  printLn !(unsetEnv "IDRIS_MLIR_T_UNSET")
  printLn !(getEnv "IDRIS_MLIR_T_UNSET")
