-- exit: 0
-- stdout: 1331246629686034420\n2\n
module Main

-- rule: PROF-TYPE-4, ELIM-G-6, PROF-GEN-4
-- Integers that are constants in the optimized module are allowed: the
-- folders compute arithmetic beyond 64 bits and casts that wrap, and data
-- with an Integer field is taken apart at compile time.
-- Was SEM-BIG-1-static-integers; SEM-BIG-1 is withdrawn at the cutover
-- (SEM-BIG-1), and its `fact 30` is gone with it (a PROF-GEN-4
-- exception, SEM-EVAL-6): `fact : Integer -> Integer` recurses on an
-- Integer, which Idris does not prove terminating, so it is not evaluated
-- and its Integer would exist at runtime. The same rejection is
-- profile/v3/reject/PROF-TYPE-4-partial-integer, and the line of output
-- 265252859812191058636308480000000 left the header.

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
