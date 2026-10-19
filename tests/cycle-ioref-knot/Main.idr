-- expect: cycle, line 18
-- message: Main.Node
module Main

import Prelude
import Data.IORef

-- A node holds an IORef that may hold a node. An IORef is an array of
-- rank 0, a cell written after it is made, so the IORef can then hold the
-- node that holds it: written into itself, it is a knot that counting
-- would never free, and the type is refused. Base's newIORef makes the
-- IORef, and a type has no place in the module, so the refusal is at the
-- first value of a type on the cycle this program builds: the Nothing.
data Node = MkNode (IORef (Maybe Node))

main : IO ()
main = do
  r <- newIORef Nothing
  writeIORef r (Just (MkNode r))
  putStrLn "a knot"
