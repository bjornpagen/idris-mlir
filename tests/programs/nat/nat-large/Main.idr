module Main

-- Naturals past the small range, 2^62 and above, are GMP integers, and
-- every Nat operation crosses between the two forms: the sum and product
-- leave the small range, the predecessor and minus come back into it, and
-- natToInteger and integerToNat keep the value either way. The base comes
-- from the input, so all of it is computed at runtime.

import Prelude
import Data.Nat

pow : Nat -> Nat -> Nat
pow b Z = 1
pow b (S k) = b * pow b k

main : IO ()
main = do
  c <- getChar
  let two = the Nat (cast (the Int (cast (ord c) - 48)))
  let p = pow two 62
  printLn p
  printLn (p + p)
  printLn (pred p)
  printLn (minus p 1 == pred p, p > pred p, compare (pred p) p)
  printLn (natToInteger (p * p))
  printLn (integerToNat (natToInteger p - 4611686018427387905))
  printLn (S (pred p) == p)
  printLn (natToInteger (integerToNat (natToInteger (p * p))) == natToInteger p * natToInteger p)
