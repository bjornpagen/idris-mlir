-- expect: elaboration, line 30
module Main

-- A type that applies `firstOf : P (xs ++ ys) n -> P xs n` to a value
-- whose index, `rev as`, is no append and reduces to none: the postponed
-- constraint, `rev as` against `xs ++ ys`, relates no two applications of
-- one name, so no match solves `xs`, and the type is refused, "Can't solve
-- constraint between: rev as and ?xs ++ ?ys". A type now matches its
-- postponed constraints before an implicit still unsolved is bound as an
-- argument of it, and that solves only what matching two applications'
-- arguments solves; the pinned Idris refused this as well.
-- The stock Idris is patched for the order (upstream/113-type-implicit-
-- binding-order), and refuses this; the type checker has the change as its
-- own code, and this test checks that it refuses this too.

import Prelude

%default total

data P : List Nat -> Nat -> Type where
  MkP : P xs n

firstOf : P (xs ++ ys) n -> P xs n
firstOf _ = MkP

rev : List Nat -> List Nat
rev [] = []
rev (x :: xs) = rev xs ++ [x]

0 reversed : (as : List Nat) -> (w : P (rev as) n) -> firstOf w = firstOf w
reversed as w = Refl

main : IO ()
main = putStrLn "unreached"
