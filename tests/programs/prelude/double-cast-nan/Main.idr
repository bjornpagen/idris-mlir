module Main

-- Casting NaN to Int crashes, after the output written so far.

import Builtin
import Prelude

partial
main : IO ()
main = do
  c <- getChar
  let x = prim__cast_IntDouble (prim__sub_Int (prim__cast_CharInt c) 48)
  putStrLn (prim__cast_DoubleString (prim__div_Double x x))
  putStrLn (prim__cast_IntString (prim__cast_DoubleInt (prim__div_Double x x)))
