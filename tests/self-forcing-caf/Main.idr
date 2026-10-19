module Main

-- A top-level lazy value whose value needs itself. Its one cell is forced,
-- and the force inside its own computation finds the cell still running:
-- the program ends there, naming the cause, instead of looping. A lazy
-- value that needs another, forced twice before it, is no such case: it
-- prints, and its output is written before the crash.

import Prelude

base : Lazy Int
base = Delay (20 + 1)

twice : Lazy Int
twice = Delay (force base + force base)

knot : Lazy Int
knot = Delay (1 + force knot)

main : IO ()
main = do
  printLn (force twice)
  printLn (force twice)
  printLn (force knot)
