-- expect: cycle, line 14
-- message: an IORef of
module Main

import Prelude
import Data.IORef

-- A node holds an IORef that may hold a node. An IORef is an array of
-- rank 0, a cell written after it is made, so the IORef can then hold the
-- node that holds it: written into itself, it is a knot that counting
-- would never free, and the type is refused. Base's newIORef makes the
-- IORef, and base's code has no place in this program's source, so the
-- refusal is at the program's own type on the cycle, which closes the knot.
data Node = MkNode (IORef (Maybe Node))

main : IO ()
main = do
  r <- newIORef Nothing
  writeIORef r (Just (MkNode r))
  putStrLn "a knot"
