module Main

-- rule: ELIM-G-10, ELIM-G-7
-- Functions that build and return strings are unfolded where they are
-- called, so their strings are still written straight to the output.

import Builtin
import IdrisMLIR.IO

showD : Double -> String
showD = prim__cast_DoubleString

showI : Int -> String
showI = prim__cast_IntString

point : Double -> Int -> String
point x n = prim__strAppend "(" (prim__strAppend (showD x) (prim__strAppend ", " (prim__strAppend (showI n) ")")))

sign : Int -> String
sign 0 = "zero"
sign n = case prim__lt_Int n 0 of
  0 => "positive"
  _ => "negative"

partial
main : IO ()
main = do
  c <- getChar
  let n = prim__sub_Int (prim__cast_CharInt c) 48
  putStrLn (point (prim__div_Double 1.0 (prim__cast_IntDouble n)) n)
  putStrLn (sign n)
  putStrLn (sign (prim__sub_Int 0 n))
