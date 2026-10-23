module Clause

import Data.Nat

%default total

data Bring : Nat -> Type where
  BringOne : Bring 1

-- A clause whose Refl refines the argument before it, written `_`: the
-- argument becomes a match on 1, and its other values are refuted only by
-- the equation inside the pair.
paired : (c : Nat) -> (Nat, c = 1) -> Bring c
paired _ (_, Refl) = BringOne

-- The frontend's Held.lteSuccCases, its second clause's `S _` solved to
-- `S Z`: the case it leaves, `{k = S (S _)} {m = Z}`, has an
-- `LTE (S (S _)) (S Z)`, empty only through `LTESucc`'s argument, an
-- `LTE (S _) Z`.
0 lteSuccCases : {k, m : Nat} -> LTE k (S m) -> Either (k = S m) (LTE k m)
lteSuccCases {k = Z} _ = Right LTEZero
lteSuccCases {k = S _} {m = Z} (LTESucc LTEZero) = Left Refl
lteSuccCases {k = S k'} {m = S m'} (LTESucc le) = case lteSuccCases le of
  Left eq => Left (cong S eq)
  Right le' => Right (LTESucc le')

-- Families whose arguments do not get smaller: the search does not take
-- them apart again, and still finds the equation beside them.
data Endless : Type where
  More : Endless -> Endless

data Up : Nat -> Type where
  Climb : Up (S n) -> Up n

endless : (b : Bool) -> (Endless, b = True) -> Nat
endless _ (_, Refl) = 0

up : (b : Bool) -> (Up 0, b = True) -> Nat
up _ (_, Refl) = 0
