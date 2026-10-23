module Main

-- Types that apply a function on an append's left part, `firstOf : P (xs
-- ++ ys) n -> P xs n`, to a value whose index is an append of two of the
-- type's locals (`sameFirst`, `statedRest`, with `ys` stated) or reduces to
-- one (`placed`: `g (x :: xs)` is `h x ++ g xs`). Only a postponed
-- constraint, `as ++ bs` against `xs ++ ys`, solves `firstOf`'s implicit,
-- by matching the two applications' arguments. The pinned Idris bound the
-- implicit, still unsolved, as a new argument of the type before it ran
-- that match, outside every local of the type, and refused each: "Can't
-- solve constraint between: ?xs [no locals in scope] and as". A type now
-- matches its postponed constraints before binding, as a right-hand side
-- does. An implicit no constraint relates is still bound as an argument
-- of the type: `tagged` takes a `Tag []` of any element type. Checking the
-- types is the test; the program only runs.
-- The stock Idris is patched for it (upstream/113-type-implicit-binding-
-- order); the type checker has the change as its own code, and this test
-- checks it.

import Prelude

%default total

data P : List Nat -> Nat -> Type where
  MkP : P xs n

firstOf : P (xs ++ ys) n -> P xs n
firstOf _ = MkP

0 sameFirst : (as, bs : List Nat) -> (w : P (as ++ bs) n) -> firstOf w = firstOf w
sameFirst as bs w = Refl

0 statedRest : (as, bs : List Nat) -> (w : P (as ++ bs) n) ->
               firstOf {ys = bs} w = firstOf {ys = bs} w
statedRest as bs w = Refl

h : Nat -> List Nat
h Z = []
h (S k) = [k]

g : List Nat -> List Nat
g [] = []
g (x :: xs) = h x ++ g xs

data Q : P xs n -> Type where
  MkQ : Q p

0 placed : (x : Nat) -> (xs : List Nat) -> (w : P (g (x :: xs)) n) -> Q (firstOf w) -> ()
placed x xs w q = ()

data Tag : List a -> Type where
  MkTag : Tag xs

0 tagged : Tag [] -> ()
tagged _ = ()

0 both : (Tag {a = Nat} [] -> (), Tag {a = String} [] -> ())
both = (tagged, tagged)

main : IO ()
main = putStrLn "checked"
