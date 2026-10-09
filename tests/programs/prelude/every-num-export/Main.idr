module Main

-- Every run-time export of Prelude.Num, each used (covers): Num's, Neg's,
-- Abs's and Integral's methods and subtract at each integer type the
-- module implements them for (Integer, Int, Int8 to Int64, Bits8 to
-- Bits64), Fractional's at Double with Num, Neg and Abs, and
-- defaultInteger, the hint that types an unconstrained literal, used
-- implicitly and explicitly. The interfaces' constructors are
-- compile-time only. A fixed-width result wraps modulo the type's width;
-- div and mod are taken at each sign. Each line is printed so that what
-- it computes is checked.

import Prelude

spaced : List String -> String
spaced [] = ""
spaced [s] = s
spaced (s :: ss) = s ++ " " ++ spaced ss

line : String -> List String -> IO ()
line label xs = putStrLn (label ++ ": " ++ spaced xs)

-- x + y, x * y, x - y, negate x, abs x, abs (negate y), div and mod at
-- each sign of y, subtract, fromInteger, and a polynomial whose
-- coefficients are literals of the type.
arith : (Show a, Num a, Neg a, Abs a, Integral a) => a -> a -> List String
arith x y =
  [ show (x + y), show (x * y), show (x - y), show (negate x), show (abs x)
  , show (abs (negate y)), show (div x y), show (mod x y)
  , show (div x (negate y)), show (mod x (negate y))
  , show (subtract y x), show (fromInteger 1000 + x), show (3 * x * x + 2 * x + 1) ]

sumOf : Num a => List a -> a
sumOf = foldr (+) (fromInteger 0)

mean : Fractional a => List a -> a
mean xs = sumOf xs / sumOf (map (const 1) xs)

main : IO ()
main = do
  line "Integer" (arith (the Integer (-123456789012345678901)) 1000000007)
  line "Int" (arith (the Int 9000000000000000000) 7)
  line "Int8" (arith (the Int8 (-100)) 7)
  line "Int16" (arith (the Int16 30000) (-7))
  line "Int32" (arith (the Int32 (-2000000000)) 3)
  line "Int64" (arith (the Int64 (-9000000000000000000)) 11)
  line "Bits8" (arith (the Bits8 200) 7)
  line "Bits16" (arith (the Bits16 65000) 9)
  line "Bits32" (arith (the Bits32 4000000000) 13)
  line "Bits64" (arith (the Bits64 18000000000000000000) 17)
  line "signed div and mod"
    [ show (div (the Integer (-7)) 2), show (mod (the Integer (-7)) 2)
    , show (div (the Int 7) (-2)), show (mod (the Int 7) (-2))
    , show (div (the Int8 (-7)) (-2)), show (mod (the Int8 (-7)) (-2))
    , show (div (the Int64 (-9)) 4), show (mod (the Int64 (-9)) 4) ]
  line "wrapping"
    [ show (the Int8 127 + 1), show (the Bits8 0 - 1), show (negate (the Bits16 1))
    , show (abs (the Int8 (-128))), show (abs (the Int32 (-2147483648)))
    , show (the Int64 9223372036854775807 * 2), show (the Bits32 65536 * 65536)
    , show (div (the Int8 (-128)) (-1)), show (div (the Int (-9223372036854775808)) (-1)) ]
  line "fromInteger"
    [ show (the Int (fromInteger 18446744073709551621)), show (the Int8 (fromInteger 200))
    , show (the Int16 (fromInteger (-32769))), show (the Int32 (fromInteger 4294967295))
    , show (the Int64 (fromInteger 9223372036854775808)), show (the Bits8 (fromInteger 300))
    , show (the Bits16 (fromInteger (-1))), show (the Bits32 (fromInteger 4294967296))
    , show (the Bits64 (fromInteger (-1))), show (the Double (fromInteger 12345678901234567890))
    , show (the Integer (fromInteger 98765432109876543210)) ]
  line "Double"
    [ show (the Double 1.5 + 0.25), show (the Double 1.5 * (-4.0)), show (the Double 1.5 - 2.0)
    , show (negate (the Double 2.5)), show (abs (the Double (-0.75))), show (abs (the Double 3.0))
    , show (the Double 1.0 / 8.0), show (recip (the Double 4.0)), show (recip (the Double (-0.5)))
    , show (subtract 0.5 (the Double 2.0)), show (mean (the (List Double) [1.0, 2.0, 4.5])) ]
  line "defaultInteger"
    [ show (2 + 3 * 4), show (10000000000 * 10000000000 - 1)
    , show ((+) @{defaultInteger} 6 7), show ((*) @{defaultInteger} 6 7)
    , show (fromInteger @{defaultInteger} 42) ]
  printLn (map (`subtract` 1) (the (List Int) [1, 2, 3]))
  printLn (sumOf (the (List Bits8) [100, 100, 100]), sumOf (the (List Integer) [100, 100, 100]))
