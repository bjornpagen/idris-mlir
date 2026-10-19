module Prog

import Prelude
import Data.IOArray.Prims

-- An array of n elements read at n, one past its end: the index's guard
-- fails, and the crash names the cause and the definition whose read
-- failed, loaded from its TTC, which keeps no location inside a term.
export
readPast : Int -> IO Int
readPast n = do
  arr <- primIO (prim__newArray n 7)
  primIO (prim__arrayGet arr n)
