-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| How two naturals compare, decided by the machine's comparison.
|||
||| The evidence each answer carries is erased: deciding costs the
||| comparisons the machine makes, on either host, and never a proof built
||| by walking the numbers, which would cost the stock host a step for each.
module Relational.Order

import Data.Nat
import Data.So

%default total

||| Which of two naturals is smaller, or that they are one.
public export
data Order : Nat -> Nat -> Type where
  Less : (0 _ : LT x y) -> Order x y
  Same : (0 _ : x = y) -> Order x y
  More : (0 _ : LT y x) -> Order x y

||| Two naturals neither of which is below the other are equal.
0 neither : (x, y : Nat) -> So (not (x < y)) -> So (not (y < x)) -> x = y
neither Z Z _ _ = Refl
neither Z (S _) below _ = absurd below
neither (S _) Z _ above = absurd above
neither (S x) (S y) below above = cong S (neither x y below above)

||| The order of two naturals: at most two comparisons.
export
order : (x, y : Nat) -> Order x y
order x y = case choose (x < y) of
  Left below => Less (ltOpReflectsLT x y below)
  Right notBelow => case choose (y < x) of
    Left above => More (ltOpReflectsLT y x above)
    Right notAbove => Same (neither x y notBelow notAbove)
