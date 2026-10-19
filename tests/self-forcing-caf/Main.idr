module Main

-- A top-level lazy value whose value needs itself. Its one cell is forced,
-- and the force inside its own computation finds the cell still running:
-- the program ends there, naming the cause, instead of looping.

import Prelude

knot : Lazy Int
knot = Delay (1 + force knot)

main : IO ()
main = printLn (force knot)
