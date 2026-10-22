module Main

import Prelude
import Rebuilds

-- The library's once passes bump its parameter and reads it no more, and
-- onceOf gives it a list it has just built: the call is exclusive, so the
-- program compiles, and the list is rebuilt in place.

main : IO ()
main = do
  c <- getChar
  printLn (onceOf (cast (ord c - ord '0')))
