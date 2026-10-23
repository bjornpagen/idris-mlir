module Escape

import Data.Vect

-- A case whose clause builds a pair whose type needs the clause's own
-- variable (`Vect n Nat`, `n` bound by the clause): no non-dependent pair
-- type outside the clause holds it, so the case is refused.
data Box : Type where
  MkBox : (n : Nat) -> Vect n Nat -> Box

size : Box -> Nat
size b =
  let (k, v) = case b of
                 MkBox n xs => (n, xs)
  in k
