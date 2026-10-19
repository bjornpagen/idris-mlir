module Main

import Prelude
import Prog

-- The closed call, then the same functions on the byte on stdin (255 at
-- the end of input), which no fold knows.
main : IO ()
main = do
  printLn Prog.result
  c <- getChar
  printLn (linearId (clamp (ord c) 9 Ok))
