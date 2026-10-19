module Main

import Prelude
import Data.IOArray.Prims

-- The refused program with the knot cut: a node holds an Int, not an array
-- of nodes, so no array's element type reaches the array again. The array
-- holds the node, which is read back.
data Node = MkNode Int

main : IO ()
main = do
  arr <- primIO (prim__newArray 1 Nothing)
  primIO (prim__arraySet arr 0 (Just (MkNode 7)))
  Just (MkNode n) <- primIO (prim__arrayGet arr 0)
    | Nothing => putStrLn "empty"
  printLn n
