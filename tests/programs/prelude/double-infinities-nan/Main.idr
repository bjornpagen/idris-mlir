module Main

-- The infinities and NaN are written as IEEE 754 spells them: inf, -inf
-- and nan, a NaN whatever its sign. They read back through `cast`, and
-- `show` puts -inf in parentheses, as any negative number. Values made from
-- stdin, so that the runtime computes them, and 1.0 / 0.0, which the
-- compiler folds through the same runtime. Chez writes Scheme's +inf.0,
-- -inf.0 and +nan.0 (chez-differs).

import Builtin
import Prelude

line : Double -> IO ()
line d = putStrLn (prim__cast_DoubleString d)

partial
main : IO ()
main = do
  c <- getChar
  let x = prim__cast_IntDouble (prim__sub_Int (prim__cast_CharInt c) 48)
  let zero = prim__sub_Double x x
  let inf = prim__div_Double x zero
  let nan = prim__div_Double zero zero
  line inf
  line (prim__negate_Double inf)
  line nan
  line (prim__negate_Double nan)
  line (prim__sub_Double inf inf)
  line (prim__mul_Double x 1.7e308)
  line (prim__div_Double 1.0 0.0)
  putStrLn (show (Just inf))
  putStrLn (show (Just (prim__negate_Double inf)))
  putStrLn (show (Just nan))
  line (cast (prim__cast_DoubleString inf))
  line (cast (prim__cast_DoubleString (prim__negate_Double inf)))
  line (cast (prim__cast_DoubleString nan))
