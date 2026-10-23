module Main

-- A Double's exact bits, carried from a literal through Prog's TTC, the
-- module and the program to its text; Prog derives each line.

import Prelude
import Prog

partial
main : IO ()
main = do
  traverse_ putStrLn Prog.pastRange
  traverse_ putStrLn Prog.subnormalDivisor
  traverse_ putStrLn Prog.zeros
