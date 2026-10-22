module Main

-- A fixed implementation whose parent is computed by a covering definition
-- that is not structurally recursive, and a function that takes the
-- implementation apart down to its parent's method by a nested pattern.

import Prelude

covering
eqVia : Nat -> Eq Nat
eqVia n = if n >= 100 then MkEq (==) (/=) else eqVia (n * 2 + 1)

interface Eq a => Keyed a where
  constructor MkKeyed
  key : a -> Nat

covering
keyedNat : Keyed Nat
keyedNat = MkKeyed @{eqVia 1} (\n => n + 1)

same : Keyed a => a -> a -> Bool
same @{MkKeyed @{MkEq eq _} _} x y = eq x y

covering
main : IO ()
main = do
  line <- getLine
  let k = the Nat (cast line)
  printLn (same @{keyedNat} 3 k)
  printLn (key @{keyedNat} k)
