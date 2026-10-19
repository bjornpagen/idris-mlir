module Main

-- A map keyed by a type its module exports without its definition (Lib's
-- Meters, which is Int there), ordered by an implementation that module
-- exports without its definition either (ordM, descending): the compiler
-- reduces the implementation all the same, and the map holds it wherever
-- it goes, as when Lib hands it out as a map of Ints.

import Prelude
import Data.SortedMap
import Lib

main : IO ()
main = do
  line <- getLine
  let n = the Int (cast line)
  let down = the (SortedMap Meters String) (fromList @{ordM} [(meters n, "n"), (meters 1, "1"), (meters (n * 2), "2n")])
  printLn (map value (keys down))
  let ints = asInts down
  printLn (keys ints)
  printLn (lookup n ints)
  printLn (keys (insert 7 "seven" ints))
