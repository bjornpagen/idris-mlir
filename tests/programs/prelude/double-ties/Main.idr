module Main

-- Where a double is exactly halfway between the two shortest texts that
-- read back as it, the one whose last digit is even is written, as IEEE
-- 754's default rounding breaks a tie: 12.8868560791015625 is
-- 12.886856079101562, in either layout and of either sign, and
-- 1125899906842624.75 is 1.1258999068426248e15, the larger, whose last
-- digit is the even one. Values made from stdin, so that the runtime
-- computes them.

import Builtin
import Prelude

line : Double -> IO ()
line d = putStrLn (prim__cast_DoubleString d)

partial
main : IO ()
main = do
  c <- getChar
  let x = prim__cast_IntDouble (prim__sub_Int (prim__cast_CharInt c) 48)
  let one = prim__div_Double x x
  line (prim__mul_Double one 12.8868560791015625)
  line (prim__mul_Double one (-0.088321685791015625))
  line (prim__mul_Double one (-26096915.4228515625))
  line (prim__mul_Double one 1125899906842624.25)
  line (prim__mul_Double one 1125899906842624.75)
  line (cast (prim__cast_DoubleString (prim__mul_Double one 12.8868560791015625)))
