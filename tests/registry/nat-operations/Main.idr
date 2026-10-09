module Main

-- The registry's NatOperation hooks: the Prelude's functions on naturals
-- (natToInteger, integerToNat, plus, mult, minus, equalNat, compareNat)
-- and Data.Nat's lte, gte, lt and gt compute on Nat's representation, a
-- big that is never negative, as Idris's own backends compute them.
-- translate.check finds none of them translated in full Core. The values
-- come from the input, so they are computed at runtime, and are large
-- enough that a unary recursion over them would not finish.

import Prelude
import Data.Nat

digit : Char -> Integer
digit c = cast (ord c) - 48

main : IO ()
main = do
  c <- getChar
  let d = digit c
  let big = d * 1000000000000000000000
  -- integerToNat clamps a negative Integer at 0, and natToInteger gives
  -- back what integerToNat was given otherwise.
  printLn (natToInteger (integerToNat (0 - d)))
  printLn (natToInteger (integerToNat big))
  printLn (natToInteger (integerToNat 0))
  let n = integerToNat big
  let m = integerToNat (d * 7)
  printLn (integerToNat (natToInteger n) == n)
  -- minus truncates at 0.
  printLn (minus m n)
  printLn (minus n m)
  printLn (n + m)
  printLn (n * m)
  printLn (equalNat n m, equalNat m m)
  printLn (compareNat n m, compareNat m n, compareNat m m)
  printLn (compare n m, n < m, n > m, n <= n, max n m)
  printLn (lte m n, gte m n, lt m m, gt n m)
  -- Nat's functions partially applied, as closures.
  printLn (map (plus 1) [m, n])
  printLn (foldr mult 1 [m, m, 2])
  -- fromInteger and cast go through integerToNat and natToInteger.
  printLn (the Nat 12 + cast (the Integer (-3)))
  printLn (cast {to = Integer} (S (S m)))
