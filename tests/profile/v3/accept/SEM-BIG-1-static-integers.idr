-- exit: 0
-- stdout: 265252859812191058636308480000000\n1331246629686034420\n2\n
module Main

-- rule: SEM-BIG-1
-- Integers are evaluated at compile time: recursion, arithmetic beyond 64
-- bits, casts that wrap, and data with Integer fields.

import IdrisMLIR.IO

fact : Integer -> Integer
fact 0 = 1
fact n = prim__mul_Integer n (fact (prim__sub_Integer n 1))

data Big : Type where
  MkBig : Integer -> Big

partial
size : Big -> Int
size (MkBig n) = prim__cast_IntegerInt (prim__div_Integer n 50)

partial
main : IO ()
main = do
  putStrLn (prim__cast_IntegerString (fact 30))
  putStrLn (prim__cast_IntString (prim__cast_IntegerInt
    (prim__mul_Integer 12345678901234567890 98765432109876543210)))
  putStrLn (prim__cast_IntString (size (MkBig 100)))
