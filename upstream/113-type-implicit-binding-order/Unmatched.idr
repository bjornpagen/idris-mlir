module Unmatched

-- An index no append matches: `xs` is still not solved, and the type is
-- refused.

data P : List Nat -> Nat -> Type where
  MkP : P xs n

firstOf : P (xs ++ ys) n -> P xs n
firstOf _ = MkP

rev : List Nat -> List Nat
rev [] = []
rev (x :: xs) = rev xs ++ [x]

0 reversed : (as : List Nat) -> (w : P (rev as) n) -> firstOf w = firstOf w
reversed as w = Refl
