-- expect: cycle, line 24
-- message: an IORef of
module Main

import Prelude
import Data.IORef

-- A node holds an IORef that may hold a node. An IORef is an array of
-- rank 0, a cell written after it is made, so the IORef can then hold the
-- node that holds it: written into itself, it is a knot that counting
-- would never free, and the type is refused. The refusal is at the first
-- IORef of the knot's type the program makes, which base's newIORef makes
-- (Data/IORef.idr, line 24), and base's diagnostics are reported where
-- its code is.
data Node = MkNode (IORef (Maybe Node))

main : IO ()
main = do
  r <- newIORef Nothing
  writeIORef r (Just (MkNode r))
  putStrLn "a knot"
