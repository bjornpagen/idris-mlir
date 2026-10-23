module Prog

import Prelude

-- A Double reaches the program by its bits: a literal is read once, to
-- the double nearest it, as IEEE 754 rounds, and every step after keeps
-- the double it was given, so each line printed is fixed by IEEE 754 and
-- by the runtime's text of a double: `inf` and `-inf`, and a finite one's
-- fewest digits that read back as it, positional from 1e-3 up to 1e10,
-- else `d.ddde<exponent>`. The values cross from this module to Main
-- through its TTC, then into the compiled module and the program. Each
-- line, derived:
--
-- `pastRange`. The largest double is (2 - 2^-52) * 2^1023, about
-- 1.7976931348623157e308; rounding to nearest takes every real at least
-- 2^1024 - 2^970 (about 1.7976931348623158e308) to infinity. 1.0e309 is
-- past it, so the literal is infinity: `inf`. Negation flips the sign bit
-- alone: `-inf`.
--
-- `subnormalDivisor`. 4.9e-324 lies between 2^-1075 and 3 * 2^-1075
-- (about 2.47e-324 and 7.41e-324), so it reads as the smallest subnormal,
-- 2^-1074. 2.2250738585072014e-308 is within 1.7e-325 of the smallest
-- normal, 2^-1022, where doubles are 2^-1074 (about 4.94e-324) apart, so
-- it reads as 2^-1022. The quotient 2^-1022 / 2^-1074 is 2^52 =
-- 4503599627370496, a double, so the division gives it exactly. Below
-- 2^52 doubles are 0.5 apart and above it 1, so the decimals that read
-- back as 2^52 fill
-- [2^52 - 0.25, 2^52 + 0.5]: no number of 15 significant digits is in it
-- (the nearest, 4503599627370500, is 4 away), so the text has all 16, in
-- scientific form past 1e10: `4.503599627370496e15`. A quotient's sign is
-- the exclusive or of its operands' signs, so the negated dividend gives
-- `-4.503599627370496e15`. A subnormal flushed to zero would make both
-- quotients infinities, and any other divisor would move them from 2^52.
--
-- `zeros`. A division of a nonzero number by a zero gives an infinity, its
-- sign the exclusive or of the operands' signs: 1.0 / 0.0 is `inf`, and
-- 1.0 / -0.0 is `-inf`, -0.0 being 0.0 with its sign bit flipped. `==`
-- finds the two zeros equal, so they share one definition: a constant
-- taken for another by `==` rather than by its bits makes the two lines
-- one.
--
-- The rest is covered by closed-double-text: the smallest subnormal's own
-- text, `5e-324`, and texts of 17 significant digits, the most a double
-- needs (2.2250738585072014e-308, 1.7976931348623157e308).

public export
pastRange : List String
pastRange =
  [ prim__cast_DoubleString 1.0e309
  , prim__cast_DoubleString (prim__negate_Double 1.0e309) ]

public export partial
subnormalDivisor : List String
subnormalDivisor =
  [ prim__cast_DoubleString (prim__div_Double 2.2250738585072014e-308 4.9e-324)
  , prim__cast_DoubleString (prim__div_Double (prim__negate_Double 2.2250738585072014e-308) 4.9e-324) ]

public export partial
zeros : List String
zeros =
  [ prim__cast_DoubleString (prim__div_Double 1.0 0.0)
  , prim__cast_DoubleString (prim__div_Double 1.0 (prim__negate_Double 0.0)) ]
