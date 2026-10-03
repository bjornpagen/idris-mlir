-- expect: dictionary field, line 14
-- message: where Lib.Meters is opaque to the program
module Main

import Prelude
import Data.SortedMap
import Lib

-- SortedMap Meters String and SortedMap Int String are two types to Idris:
-- Meters is opaque here, with its own (descending) Ord. The compiler sees
-- through Meters, which Lib exports without its definition, so the two are
-- one type with one Ord; it names Meters, rather than give the maps two
-- data instances, which Lib could convert one into the other.
main : IO ()
main = do
  line <- getLine
  let n = the Int (cast line)
  let down = the (SortedMap Meters String) (fromList @{ordM} [(meters n, "n"), (meters 1, "1"), (meters (n * 2), "2n")])
  let up = the (SortedMap Int String) (fromList [(n, "n"), (1, "1"), (n * 2, "2n")])
  printLn (map value (keys down))
  printLn (keys up)
