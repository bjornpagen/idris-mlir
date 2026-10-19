module Main

import Prelude
import Prog

-- A week of n steps from Monday is day n modulo 7, in a closed call and
-- for n the byte on stdin (255 at the end of input).
main : IO ()
main = do
  printLn Prog.result
  c <- getChar
  printLn (index (stepN (ord c) Mon))
