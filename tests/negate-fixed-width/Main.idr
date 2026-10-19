module Main

-- Idris's negation at every fixed width, called directly: two's-complement
-- negation, the width's subtraction from zero. The most negative signed
-- value is its own negation, the greatest negates to one above the least,
-- zero to zero, and an unsigned width wraps: 2^(w-1) is its own negation.

import Prelude

main : IO ()
main = do
  printLn (prim__negate_Int8 5)
  printLn (prim__negate_Int8 (-128))
  printLn (prim__negate_Int8 127)
  printLn (prim__negate_Int8 0)
  printLn (prim__negate_Int16 (-32768))
  printLn (prim__negate_Int16 32767)
  printLn (prim__negate_Int32 1)
  printLn (prim__negate_Int32 (-2147483648))
  printLn (prim__negate_Int64 (-9223372036854775808))
  printLn (prim__negate_Int64 9223372036854775807)
  printLn (prim__negate_Int 7)
  printLn (prim__negate_Int (-9223372036854775808))
  printLn (prim__negate_Bits8 1)
  printLn (prim__negate_Bits8 0)
  printLn (prim__negate_Bits8 128)
  printLn (prim__negate_Bits8 255)
  printLn (prim__negate_Bits16 2)
  printLn (prim__negate_Bits16 32768)
  printLn (prim__negate_Bits32 0)
  printLn (prim__negate_Bits32 1)
  printLn (prim__negate_Bits64 1)
  printLn (prim__negate_Bits64 18446744073709551615)
  printLn (prim__negate_Bits64 9223372036854775808)
