module Main

import Prelude
import Prog

-- The divisor is the digit on stdin, then 0 in a closed call.
partial
main : IO ()
main = do
  c <- getChar
  printLn (Prog.divide 10 (ord c - ord '0'))
  printLn Prog.result
