module Main

import Prelude
import Data.IORef

-- The refused program with the knot cut: a node holds an Int, not an IORef
-- that may hold a node, so the IORef's element type never reaches the
-- IORef again. Written and read back.
data Node = MkNode Int

main : IO ()
main = do
  r <- newIORef Nothing
  writeIORef r (Just (MkNode 7))
  Just (MkNode n) <- readIORef r
    | Nothing => putStrLn "empty"
  printLn n
