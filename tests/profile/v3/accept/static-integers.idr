-- exit: 0
-- stdout: 1331246629686034420\n2\n
module Main

-- Integers that are constants in the optimized module are allowed: the
-- folders compute arithmetic beyond 64 bits and casts that wrap, and data
-- with an Integer field is taken apart at compile time. An Integer that
-- would exist at runtime is rejected:
-- profile/v3/reject/runtime-integer-partial.

import Prelude

data Big : Type where
  MkBig : Integer -> Big

partial
size : Big -> Int
size (MkBig n) = prim__cast_IntegerInt (prim__div_Integer n 50)

partial
main : IO ()
main = do
  putStrLn (prim__cast_IntString (prim__cast_IntegerInt
    (prim__mul_Integer 12345678901234567890 98765432109876543210)))
  putStrLn (prim__cast_IntString (size (MkBig 100)))
