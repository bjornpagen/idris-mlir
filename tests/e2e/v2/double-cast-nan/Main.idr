module Main

-- rule: SEM-DBL-4, LOW-DBL-1, SEM-CRASH-1
-- Casting NaN to Int crashes, after the output written so far.

import Builtin
import IdrisMLIR.IO

partial
main : IO ()
main = do
  c <- getChar
  let x = prim__cast_IntDouble (prim__sub_Int (prim__cast_CharInt c) 48)
  putStrLn (prim__cast_DoubleString (prim__div_Double x x))
  putStrLn (prim__cast_IntString (prim__cast_DoubleInt (prim__div_Double x x)))
