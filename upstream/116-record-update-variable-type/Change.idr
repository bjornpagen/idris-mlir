module Change

import Data.Vect

-- A type-changing update in a let without a signature: the record's own
-- type, `Sized n`, names the record, and the update's type is
-- `Sized (S n)`, which the let's body fixes.

record Sized (n : Nat) where
  constructor MkSized
  items : Vect n Nat
  name : String

grow : Nat -> Sized n -> Sized (S n)
grow x c =
  let c' = { items := x :: c.items } c
  in c'
