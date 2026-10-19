module Main

-- A subnormal double is written as any other, with the fewest significant
-- digits that read back as it: the least is 5e-324. Its text reads back
-- through `cast`, and `show` puts a negative one in parentheses. Values
-- made from stdin, so that the runtime computes them.

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
  line (prim__mul_Double one 4.9e-324)
  line (prim__mul_Double x 5.0e-324)
  line (prim__negate_Double (prim__mul_Double one 2.5e-310))
  line (prim__div_Double 2.2250738585072014e-308 (prim__add_Double one one))
  line (prim__sub_Double 2.2250738585072014e-308 (prim__mul_Double one 4.9e-324))
  line (prim__mul_Double one 2.2250738585072014e-308)
  putStrLn (show (Just (prim__negate_Double (prim__mul_Double x 5.0e-324))))
  line (cast (prim__cast_DoubleString (prim__mul_Double x 5.0e-324)))
