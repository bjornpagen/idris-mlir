module CaseBlock

import Data.Nat

%default total

-- The frontend's Held.aloneWritten: a case block whose scrutinee holds an
-- equation on an implicit of the function, matched by Refl. The coverage
-- check splits the implicit, which the match refines to 1, and proposes
-- 0 and S (S _) as missing, the scrutinee unsplit: `one : LTE 1 0`
-- refutes the first, and only the equation inside the triple, `S (S _) =
-- 1`, the second.

three : (x, c, y : Nat) -> x + (c + y) = 1 -> LTE 1 c -> (x = 0, c = 1, y = 0)
three Z (S Z) Z Refl _ = (Refl, Refl, Refl)
three Z (S Z) (S y) Refl _ impossible
three Z (S (S c)) y Refl _ impossible
three Z Z y _ one = void (succNotLTEzero one)
three (S x) Z y _ one = void (succNotLTEzero one)
three (S x) (S c) y eq _ = void (SIsNotZ (trans (plusSuccRightSucc x (c + y)) (cong pred eq)))

data Bring : Nat -> Type where
  BringOne : Bring 1

bringing : Nat -> Nat
bringing n = n

0 alone : {c : Nat} -> (x, y : Nat) -> x + (c + y) = 1 -> LTE 1 c -> Bring (bringing c)
alone x y eq one = case three x c y eq one of
  (_, Refl, _) => BringOne

aloneKept : {c : Nat} -> (x, y : Nat) -> x + (c + y) = 1 -> LTE 1 c -> Bring (bringing c)
aloneKept x y eq one = case three x c y eq one of
  (_, Refl, _) => BringOne

-- The frontend's Graph.landsInto: the equation inside a dependent pair,
-- refining the function's argument `a` to `Closed x`; `Open` is proposed
-- as missing, refuted only by `Open = Closed x` inside the pair. The
-- scrutinee is a call of an argument, a pair claimed for any `Landing`,
-- which no closed function can give for `Open`.
data Landing = Closed Nat | Open

0 closedBelow : (a : Landing) -> (k : Nat) ->
                ((l : Landing) -> (j : Nat) -> (x : Nat ** (l = Closed x, LTE x j))) ->
                Bring 1
closedBelow a k joined = case joined a k of
  (x ** (Refl, _)) => BringOne
