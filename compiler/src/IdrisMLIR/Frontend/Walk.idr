-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| What a walk over the context's definitions has entered, each at most
||| once, and why the walk ends.
|||
||| Every definition has its place in the context, a non-negative `Int`. A
||| walk records the places it has entered in a binary tree over the bits
||| of a place, and entering a place it has not entered leaves fewer free:
||| that count is the measure a walk recurses on, so a walk that enters a
||| definition before it walks what the definition refers to ends however
||| the definitions refer to one another. A name with no place, which no
||| loaded definition has, is never entered.
module IdrisMLIR.Frontend.Walk

import Core.Context

import Control.WellFounded
import Data.DPair
import Data.Nat
import Data.Vect

%default total

||| The places entered below a node of `d` levels: none, the one place a
||| leaf stands for, or those of each half.
data Seen : Nat -> Type where
  None : Seen d
  Leaf : Seen Z
  Split : Seen d -> Seen d -> Seen (S d)

||| The places not entered below a node.
free : {d : Nat} -> Seen d -> Nat
free {d} None = power 2 d
free Leaf = 0
free (Split l r) = free l + free r

||| What a walk has entered, over a tree as deep as the context needs.
export
record Walked where
  constructor MkWalked
  depth : Nat
  seen : Seen depth

export
Sized Walked where
  size w = free w.seen

||| A walk that has entered nothing yet. A place is a non-negative `Int`,
||| so 63 levels hold every place there is.
export
start : Walked
start = MkWalked 63 None

||| Fewer on the right of a sum is fewer in the sum.
0 rightOf : (a : Nat) -> LT b c -> LT (a + b) (a + c)
rightOf a p = rewrite plusSuccRightSucc a b in plusLteMonotoneLeft a (S b) c p

||| Fewer than `n` on the right of `n` is fewer than twice `n`.
0 leftOf : (n : Nat) -> LT b n -> LT (n + b) (n + (n + 0))
leftOf n p = rewrite plusZeroRightNeutral n in rightOf n p

||| A tree holding only the place at `path`, which leaves one fewer free.
only : {d : Nat} -> (path : Vect d Bool) -> Subset (Seen d) (\t => LT (free t) (power 2 d))
only [] = Element Leaf (LTESucc LTEZero)
only {d = S k} (False :: bs) =
  let Element t p = only bs in
  Element (Split t None) (rewrite plusZeroRightNeutral (power 2 k) in plusLteMonotoneRight (power 2 k) (S (free t)) (power 2 k) p)
only {d = S k} (True :: bs) =
  let Element t p = only bs in
  Element (Split None t) (leftOf (power 2 k) p)

||| The tree with the place at `path` entered, which leaves fewer free;
||| nothing when it was entered already.
enterAt : {d : Nat} -> (path : Vect d Bool) -> (t : Seen d) -> Maybe (Subset (Seen d) (\t' => LT (free t') (free t)))
enterAt path None = Just (only path)
enterAt [] Leaf = Nothing
enterAt (False :: bs) (Split l r) = case enterAt bs l of
  Just (Element l' p) => Just (Element (Split l' r) (plusLteMonotoneRight (free r) (S (free l')) (free l) p))
  Nothing => Nothing
enterAt (True :: bs) (Split l r) = case enterAt bs r of
  Just (Element r' p) =>
    Just (Element (Split l r') (rightOf (free l) p))
  Nothing => Nothing

||| The bits of a place, lowest first; nothing for a place the tree is
||| not deep enough to hold.
pathOf : (d : Nat) -> Int -> Maybe (Vect d Bool)
pathOf Z i = if i == 0 then Just [] else Nothing
pathOf (S k) i = if i < 0 then Nothing else (mod i 2 == 1 ::) <$> pathOf k (div i 2)

||| The walk with a definition entered, by its name, which leaves fewer to
||| enter; nothing when it was entered already, or has no place.
export
enter : Context -> Name -> (w : Walked) -> Maybe (Subset Walked (\w' => Smaller w' w))
enter gam n (MkWalked d t) = do
  i <- getNameID n gam
  path <- pathOf d i
  Element t' p <- enterAt path t
  Just (Element (MkWalked d t') p)

||| A walk after another has entered no more than it.
public export
0 NoMore : Walked -> Walked -> Type
NoMore w' w = LTE (size w') (size w)

export
0 noMore : (w : Walked) -> NoMore w w
noMore w = reflexive

export
0 fewer : Smaller w' w -> NoMore w' w
fewer = lteSuccLeft

export
0 thenNoMore : NoMore w2 w1 -> NoMore w1 w -> NoMore w2 w
thenNoMore p q = transitive p q

export
0 thenFewer : NoMore w2 w1 -> Smaller w1 w -> Smaller w2 w
thenFewer p q = transitive (LTESucc p) q

export
0 fewerThen : Smaller w2 w1 -> NoMore w1 w -> Smaller w2 w
fewerThen q p = transitive q p
