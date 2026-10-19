module Main

import Prelude
import Data.SortedMap
import Lib

-- As the refused program, with Lib's Meters a data type: the map of Meters
-- is ordered by ordM (descending), the map of Int by Int's Ord, and two keys
-- that are equal are one key.
main : IO ()
main = do
  line <- getLine
  let n = the Int (cast line)
  let down = the (SortedMap Meters String) (fromList @{ordM} [(meters n, "n"), (meters 1, "1"), (meters (n * 2), "2n")])
  let up = the (SortedMap Int String) (fromList [(n, "n"), (1, "1"), (n * 2, "2n")])
  printLn (map value (keys down))
  printLn (keys up)
