module Main

-- An implementation that mentions a runtime value only where Idris erases
-- it is a compile-time value all the same: `Foldable (Vect n)` takes the
-- length with quantity 0, so `sum` over a vector whose length is a runtime
-- argument specializes as over any other vector, whether the instance knows
-- the length's shape (`S k`, which Res needs) or not.

import Prelude
import Data.Vect

Res : Nat -> Type
Res Z = String
Res (S _) = Integer

total
withLength : (n : Nat) -> Vect n Int -> Int
withLength n xs = sum xs + cast n

total
shaped : (n : Nat) -> Res n -> Vect n Int -> Integer
shaped Z s xs = cast (length s) + cast (sum xs)
shaped (S k) r xs = r + cast (sum xs)

main : IO ()
main = do
  line <- getLine
  let k = the Nat (cast line)
  printLn (withLength k (replicate k 7))
  printLn (withLength (S k) (1 :: replicate k 7))
  printLn (shaped (S k) 100 (2 :: replicate k 3))
  printLn (shaped Z "abc" [])
