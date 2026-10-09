-- expect: cycle, line 15
-- message: Main.Node -> array of
module Main

import Prelude
import Data.IOArray.Prims

-- A node holds an array of nodes, as base's IOArray holds its elements (an
-- array of Maybe elem, here without the size beside it): an array can
-- then hold the node that holds it. Written into its own slot, the array
-- is a knot that counting would never free, so the type is refused at the
-- definition that makes the array.
data Node = MkNode (ArrayData (Maybe Node))

main : IO ()
main = do
  arr <- primIO (prim__newArray 1 Nothing)
  primIO (prim__arraySet arr 0 (Just (MkNode arr)))
  putStrLn "a knot"
