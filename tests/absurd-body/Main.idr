module Main

import Prelude
import Prog

-- The closed call, then `get` of a value made from the byte on stdin (255
-- at the end of input), which no fold knows: the branch that calls `never`
-- is still never taken.
main : IO ()
main = do
  printLn Prog.result
  c <- getChar
  printLn (get (A (ord c)))
