module Main

-- rule: SEM-DBL-1, SEM-DBL-2, SEM-DBL-3, SEM-DBL-4, SEM-DBL-5, LOW-DBL-1, LOW-DBL-2, LOW-DBL-3, PROF-PRIM-5
-- Double arithmetic, libm functions, casts and printing on a value read at
-- run time, so that nothing folds; the stock Chez backend is the oracle.

import Builtin
import Prelude

line : Double -> IO ()
line d = putStrLn (prim__cast_DoubleString d)

int : Int -> IO ()
int n = putStrLn (prim__cast_IntString n)

-- A primitive comparison's result.
bool : Int -> IO ()
bool 0 = putStrLn "no"
bool _ = putStrLn "yes"

-- 1 + 1/2 + ... + 1/n
partial
harmonic : Double -> Double -> Double
harmonic acc k = case prim__lte_Double k 0.0 of
  0 => harmonic (prim__add_Double acc (prim__div_Double 1.0 k)) (prim__sub_Double k 1.0)
  _ => acc

partial
main : IO ()
main = do
  c <- getChar
  let x = prim__cast_IntDouble (prim__sub_Int (prim__cast_CharInt c) 48)
  let zero = prim__sub_Double x x
  line x
  line (prim__div_Double x 3.0)
  line (prim__mul_Double x 1.0e22)
  line (prim__mul_Double x 1.0e-10)
  line (prim__mul_Double x 1.0e9)
  line (prim__mul_Double x 1.0e-4)
  line (prim__div_Double 1.0 (prim__mul_Double x 1000.0))
  line (prim__negate_Double x)
  line (prim__mul_Double zero (prim__negate_Double x))
  line zero
  line (prim__div_Double x zero)
  line (prim__div_Double (prim__negate_Double x) zero)
  line (prim__div_Double zero zero)
  line (prim__mul_Double x 5.0e-324)
  line (prim__mul_Double x 2.2250738585072014e-308)
  line (prim__mul_Double x 1.7e308)
  line (prim__doubleExp x)
  line (prim__doubleLog x)
  line (prim__doublePow x 0.5)
  line (prim__doublePow x 2.0)
  line (prim__doubleSin x)
  line (prim__doubleCos x)
  line (prim__doubleTan x)
  line (prim__doubleASin (prim__div_Double 1.0 x))
  line (prim__doubleACos (prim__div_Double 1.0 x))
  line (prim__doubleATan x)
  line (prim__doubleSqrt x)
  line (prim__doubleFloor (prim__div_Double x 2.0))
  line (prim__doubleCeiling (prim__div_Double x 2.0))
  line (prim__doubleFloor (prim__negate_Double (prim__div_Double x 2.0)))
  line (harmonic 0.0 (prim__mul_Double x 1000.0))
  int (prim__cast_DoubleInt (prim__div_Double (prim__mul_Double x 1000.0) 3.0))
  int (prim__cast_DoubleInt (prim__negate_Double (prim__div_Double x 2.0)))
  int (prim__cast_DoubleInt (prim__mul_Double x 1.0e19))
  int (prim__cast_DoubleInt (prim__mul_Double x 1.0e30))
  bool (prim__lt_Double x 7.5)
  bool (prim__eq_Double (prim__div_Double zero zero) (prim__div_Double zero zero))
  bool (prim__eq_Double zero (prim__negate_Double zero))
  bool (prim__gte_Double x 7.0)
