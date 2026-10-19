module Prog

import Prelude
import Data.IOArray.Prims

-- An array of n elements read at i: the index's guard fails outside
-- 0 <= i < n, and the crash names the cause and the definition whose read
-- failed, loaded from its TTC, which keeps no location inside a term.
export
readAt : Int -> Int -> IO Int
readAt n i = do
  arr <- primIO (prim__newArray n 7)
  primIO (prim__arrayGet arr i)
