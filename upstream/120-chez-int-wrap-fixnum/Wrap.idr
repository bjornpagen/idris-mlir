module Wrap

import Data.String

-- Every fixed-width integer type's arithmetic at the values where a
-- result wraps: each type's bounds, one past them, and the bounds of a
-- Chez fixnum (+-2^60), which the Int and Bits64 results cross, with
-- inputs that are bignums before they are cast. Each line is a type and
-- its results; the expected output is what the stock Chez support gives.

-- 2^60, the first integer past a 64-bit Chez fixnum.
fixnumEnd : Integer
fixnumEnd = 1152921504606846976

-- The integers each type is given: around zero, around the fixnum's
-- bounds, around each width's bounds, and bignums.
inputs : List Integer
inputs =
  [ 0, 1, -1, 2, -2
  , fixnumEnd - 1, fixnumEnd, fixnumEnd + 1, - fixnumEnd, - fixnumEnd - 1
  , 127, 128, -128, -129, 255, 256
  , 32767, 32768, -32768, -32769, 65535, 65536
  , 2147483647, 2147483648, -2147483648, -2147483649, 4294967295, 4294967296
  , 9223372036854775807, 9223372036854775808, -9223372036854775808, -9223372036854775809
  , 18446744073709551615, 18446744073709551616
  , 1267650600228229401496703205379, -1267650600228229401496703205379 ]

-- A type's results on one input: the cast, then sums, differences,
-- products and a quotient that carry it past each bound.
results : (Num t, Neg t, Integral t, Show t) => (Integer -> t) -> Integer -> List String
results from x =
  let v = from x in
  map show [ v, v + 1, v - 1, v + v, v * v, v * 3, negate v, v `div` 2, v - from fixnumEnd, v + from fixnumEnd ]

line : String -> (Integer -> List String) -> IO ()
line name f = traverse_ (\x => putStrLn (name ++ " " ++ show x ++ ": " ++ unwords (f x))) inputs

main : IO ()
main = do
  line "Int" (results (the (Integer -> Int) cast))
  line "Int8" (results (the (Integer -> Int8) cast))
  line "Int16" (results (the (Integer -> Int16) cast))
  line "Int32" (results (the (Integer -> Int32) cast))
  line "Int64" (results (the (Integer -> Int64) cast))
  line "Bits8" (results (the (Integer -> Bits8) cast))
  line "Bits16" (results (the (Integer -> Bits16) cast))
  line "Bits32" (results (the (Integer -> Bits32) cast))
  line "Bits64" (results (the (Integer -> Bits64) cast))
