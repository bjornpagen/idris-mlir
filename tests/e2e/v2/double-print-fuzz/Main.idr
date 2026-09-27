module Main

-- rule: SEM-DBL-5, LOW-DBL-2, TEST-DIFF-1
-- Prints 30000 doubles built from pseudo-random bit patterns (any bits,
-- moderate exponents and subnormals) and 15000 whose shortest digits end in
-- a decimal tie, and compares the text with the stock Chez backend. The
-- count comes from stdin so that nothing folds.

import Builtin
import IdrisMLIR.IO

u : Int -> Bits64
u = prim__cast_IntBits64

pow2 : Bits64
pow2 = u 4503599627370496

-- The double with bits `b`, computed exactly: mantissa times a power of 2.
partial
fromBits : Bits64 -> Double
fromBits b =
  let mant = prim__mod_Bits64 b pow2
      rest = prim__div_Bits64 b pow2
      e = prim__mod_Bits64 rest (u 2048)
      m = prim__cast_Bits64Double mant
      magnitude = case prim__eq_Bits64 e (u 2047) of
        0 => case prim__eq_Bits64 e (u 0) of
          0 => prim__mul_Double (prim__add_Double m 4503599627370496.0)
                 (prim__doublePow 2.0 (prim__cast_IntDouble (prim__sub_Int (prim__cast_Bits64Int e) 1075)))
          _ => prim__mul_Double m (prim__doublePow 2.0 (prim__negate_Double 1074.0))
        _ => case prim__eq_Bits64 mant (u 0) of
          0 => prim__div_Double 0.0 0.0
          _ => prim__div_Double 1.0 0.0
  in case prim__lt_Bits64 rest (u 2048) of
       0 => prim__negate_Double magnitude
       _ => magnitude

next : Bits64 -> Bits64
next s = prim__add_Bits64 (prim__mul_Bits64 s (u 6364136223846793005)) (u 1442695040888963407)

-- Mode 0: any bits; 1: exponent near 1023; 2: subnormal.
partial
shape : Int -> Bits64 -> Bits64
shape 0 s = s
shape 1 s = prim__add_Bits64 (prim__mod_Bits64 s pow2)
              (prim__mul_Bits64 (prim__add_Bits64 (u 973) (prim__mod_Bits64 (prim__div_Bits64 s (u 7)) (u 100))) pow2)
shape _ s = prim__div_Bits64 (prim__mod_Bits64 s pow2) (prim__add_Bits64 (u 1) (prim__mod_Bits64 (prim__div_Bits64 s (u 3)) (u 1000000)))

partial
loop : Int -> Bits64 -> IO ()
loop 0 s = pure ()
loop n s = do
  let s' = next s
  putStrLn (prim__cast_DoubleString (fromBits (shape (prim__mod_Int n 3) (prim__div_Bits64 s' (u 2)))))
  putStrLn (prim__cast_DoubleString (fromBits s'))
  -- 2^50 <= n < 2^51 has 16 digits, so n + 0.25 is a tie at 17 digits.
  let t = prim__add_Bits64 (u 1125899906842624) (prim__mod_Bits64 s' (u 1125899906842624))
  putStrLn (prim__cast_DoubleString (prim__add_Double (prim__cast_Bits64Double t) 0.25))
  loop (prim__sub_Int n 1) s'

partial
main : IO ()
main = do
  c <- getChar
  loop (prim__mul_Int 15000 (prim__sub_Int (prim__cast_CharInt c) 48)) (u 42)
