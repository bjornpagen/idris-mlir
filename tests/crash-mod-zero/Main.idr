module Main

import Prelude
import Prog

-- The divisor is the byte on stdin plus one, so 256, which is 0, at the
-- end of input (getChar's 255); then 256 in a closed call.
partial
main : IO ()
main = do
  c <- getChar
  printLn (prim__cast_Bits8Int (Prog.rem 10 (ord c + 1)))
  printLn Prog.result
