module Main

-- A closure read out of a family's field, used where its caller's type
-- names the indices: `viaEquivalence`'s `No` arm composes the `Not a` its
-- `Dec a` holds with the equivalence, at `a = (1 = 1)`. The family is keyed
-- with the indices of `a` left out, so its field's closure type holds them
-- unknown, and the closure is given where the caller's type states them.

import Decidable.Equality

answer : Dec a -> String
answer (Yes _) = "yes"
answer (No _) = "no"

main : IO ()
main = do
  putStrLn (answer (viaEquivalence (MkEquivalence id id) (decEq (the Nat 1) 1)))
  putStrLn (answer (viaEquivalence (MkEquivalence id id) (decEq (the Nat 1) 2)))
