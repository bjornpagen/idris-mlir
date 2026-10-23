module Main

-- Covering definitions in which a `Refl` matched inside a pair, or inside a
-- case block's scrutinee, refines an argument the coverage tree then
-- splits: the argument's other values are proposed as missing, each with
-- the argument that holds the equation unsplit, and only the emptiness of
-- that argument's type refutes them (`(Nat, 0 = 1)`; `LTE (S (S k)) (S
-- Z)`, whose `LTESucc` takes an `LTE (S k) Z`). The pinned Idris called a
-- type empty only when every constructor's return type conflicts with it,
-- and refused every definition here but `three`. A type is now also empty
-- when each constructor that fits it takes an argument of an empty type,
-- looked into only while that type is smaller, so `Endless` and `Up` are
-- not taken apart again. `closedBelow`'s scrutinee is a call of its
-- argument, a pair proved for any `Landing`, which no closed function can
-- give for `Open`. In `atHead`, `atNamed` and `clauses` the case proposed,
-- `MkHead Nothing (_ :: _)`, has a dependent pair unsplit whose parts each
-- have a value alone and none together: its equation holds `ts = _ :: _`,
-- under which `AllR [] ts` is empty. A type with one constructor holds
-- what its constructor's return type holds (`Refl`'s two sides equal) and
-- what its arguments' types hold, and its arguments are looked into again
-- under that, so the case is refuted, as the impossible clause of
-- `written` that names it is.
-- The stock Idris is patched for it (upstream/111-coverage-nested-empty-
-- type); the type checker has the change as its own code, and this test
-- checks it.

import Prelude
import Data.Nat

%default total

data Bring : Nat -> Type where
  BringOne : Bring 1

brought : Bring n -> Nat
brought BringOne = 1

three : (x, c, y : Nat) -> x + (c + y) = 1 -> LTE 1 c -> (x = 0, c = 1, y = 0)
three Z (S Z) Z Refl _ = (Refl, Refl, Refl)
three Z (S Z) (S y) Refl _ impossible
three Z (S (S c)) y Refl _ impossible
three Z Z y _ one = void (succNotLTEzero one)
three (S x) Z y _ one = void (succNotLTEzero one)
three (S x) (S c) y eq _ = void (SIsNotZ (trans (plusSuccRightSucc x (c + y)) (cong pred eq)))

bringing : Nat -> Nat
bringing n = n

0 alone : {c : Nat} -> (x, y : Nat) -> x + (c + y) = 1 -> LTE 1 c -> Bring (bringing c)
alone x y eq one = case three x c y eq one of
  (_, Refl, _) => BringOne

aloneKept : {c : Nat} -> (x, y : Nat) -> x + (c + y) = 1 -> LTE 1 c -> Bring (bringing c)
aloneKept x y eq one = case three x c y eq one of
  (_, Refl, _) => BringOne

data Landing = Closed Nat | Open

0 closedBelow : (a : Landing) -> (k : Nat) ->
                ((l : Landing) -> (j : Nat) -> (x : Nat ** (l = Closed x, LTE x j))) ->
                Bring 1
closedBelow a k joined = case joined a k of
  (x ** (Refl, _)) => BringOne

paired : (c : Nat) -> (Nat, c = 1) -> Bring c
paired _ (_, Refl) = BringOne

0 lteSuccCases : {k, m : Nat} -> LTE k (S m) -> Either (k = S m) (LTE k m)
lteSuccCases {k = Z} _ = Right LTEZero
lteSuccCases {k = S _} {m = Z} (LTESucc LTEZero) = Left Refl
lteSuccCases {k = S k'} {m = S m'} (LTESucc le) = case lteSuccCases le of
  Left eq => Left (cong S eq)
  Right le' => Right (LTESucc le')

data Endless : Type where
  More : Endless -> Endless

data Up : Nat -> Type where
  Climb : Up (S n) -> Up n

endless : (b : Bool) -> (Endless, b = True) -> Nat
endless _ (_, Refl) = 0

up : (b : Bool) -> (Up 0, b = True) -> Nat
up _ (_, Refl) = 0

data AllR : List Nat -> List Nat -> Type where
  Nil : AllR [] []
  (::) : (t : Nat) -> AllR xs ts -> AllR (x :: xs) (t :: ts)

data Head = MkHead (Maybe Nat) (List Nat)

atHead : (r : Head) -> (ts : List Nat ** (r = MkHead Nothing ts, AllR [] ts)) -> Nat
atHead r p = case p of
  ([] ** (Refl, [])) => Z

0 atNamed : (r : Head) -> (a : Maybe Nat ** ts : List Nat ** (r = MkHead a ts, a = a, AllR [] ts)) -> Nat
atNamed r p = case p of
  (a' ** [] ** (Refl, _, [])) => Z

clauses : (r : Head) -> (ts : List Nat ** (r = MkHead Nothing ts, AllR [] ts)) -> Nat
clauses (MkHead Nothing []) ([] ** (Refl, [])) = Z

written : (r : Head) -> (ts : List Nat ** (r = MkHead Nothing ts, AllR [] ts)) -> Nat
written (MkHead Nothing []) ([] ** (Refl, [])) = Z
written (MkHead Nothing (_ :: _)) (_ ** (Refl, _)) impossible

main : IO ()
main = do
  printLn (brought (aloneKept {c = 1} 0 0 Refl (LTESucc LTEZero)))
  printLn (brought (paired 1 (5, Refl)))
  printLn (atHead (MkHead Nothing []) ([] ** (Refl, [])))
