-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| A vector held so that a position is read in as many steps as a tree
||| over it is deep, with the evidence that what is read is the vector's
||| element there.
|||
||| A `Vect` walks every position before the one it reads, so reading a
||| table of n once per writer costs n per read. The tree is made once from
||| the vector, each node the element between the part before it and the
||| part after, the two within one of each other in length; a read compares
||| the position's number with the length of the part before, which both
||| hosts do at once, since a `Nat` and a `Fin` are integers on each and
||| `natToFinLT` and `finToNat` the identity. What a read returns carries,
||| at quantity 0, that it is `Vect.index` of the vector there, so every
||| proof stated over the vector holds of what is read.
module IdrisMLIR.Frontend.Growth.Indexed

import IdrisMLIR.Proof.Growth

import Control.WellFounded
import Data.DPair
import Data.Fin
import Data.Fin.Properties
import Data.Nat
import Data.Vect

%default total

------------------------------------------------------------------------------
-- The tree
------------------------------------------------------------------------------

||| A vector held as a tree: no element, or a node holding the element
||| between the part of the vector before it, m long, and the part after.
||| The vector is the index, so a tree holds exactly the vector it is
||| indexed by.
public export
data Indexed : Vect n a -> Type where
  Bare : Indexed []
  Node : (m : Nat) -> {0 xs : Vect m a} -> {0 k : Nat} -> {0 ys : Vect k a} ->
         Indexed xs -> (x : a) -> Indexed ys -> Indexed (xs ++ x :: ys)

------------------------------------------------------------------------------
-- Reading a position
------------------------------------------------------------------------------

-- Where the position numbered q is, at a node whose part before is m long:
-- in the part before, at the node, or j into the part after.
data Placed : (m, q : Nat) -> Type where
  Before : (0 _ : LT q m) -> Placed m q
  AtNode : (0 _ : q = m) -> Placed m q
  After : (j : Nat) -> (0 _ : q = m + S j) -> Placed m q

-- What comparing q with m says of them.
0 comparedBelow : (q, m : Nat) -> compareNat q m = LT -> LT q m
comparedBelow Z Z Refl impossible
comparedBelow Z (S m) _ = LTESucc LTEZero
comparedBelow (S q) Z Refl impossible
comparedBelow (S q) (S m) eq = LTESucc (comparedBelow q m eq)

0 comparedEqual : (q, m : Nat) -> compareNat q m = EQ -> q = m
comparedEqual Z Z _ = Refl
comparedEqual Z (S m) Refl impossible
comparedEqual (S q) Z Refl impossible
comparedEqual (S q) (S m) eq = cong S (comparedEqual q m eq)

0 comparedAbove : (q, m : Nat) -> compareNat q m = GT -> q = m + S (minus q (S m))
comparedAbove Z Z Refl impossible
comparedAbove Z (S m) Refl impossible
comparedAbove (S q) Z _ = rewrite minusZeroRight q in Refl
comparedAbove (S q) (S m) eq = cong S (comparedAbove q m eq)

-- Where q is, by the machine's comparison of q with m.
placedBy : (m, q : Nat) -> (o : Ordering) -> (0 _ : compareNat q m = o) -> Placed m q
placedBy m q LT eq = Before (comparedBelow q m eq)
placedBy m q EQ eq = AtNode (comparedEqual q m eq)
placedBy m q GT eq = After (minus q (S m)) (comparedAbove q m eq)

placed : (m, q : Nat) -> Placed m q
placed m q = placedBy m q (compareNat q m) Refl

0 unS : the Nat (S a) = S b -> a = b
unS Refl = Refl

-- The element at a position before the node is the part before's, at the
-- position numbered alike.
0 indexBefore : (xs : Vect m a) -> (rest : Vect r a) -> (pos : Fin (m + r)) -> (f : Fin m) ->
                finToNat f = finToNat pos -> Vect.index pos (xs ++ rest) = Vect.index f xs
indexBefore [] rest pos f _ = absurd f
indexBefore (x :: xs) rest FZ FZ _ = Refl
indexBefore (x :: xs) rest FZ (FS f) same = void (SIsNotZ same)
indexBefore (x :: xs) rest (FS pos) FZ same = void (SIsNotZ (sym same))
indexBefore (x :: xs) rest (FS pos) (FS f) same = indexBefore xs rest pos f (unS same)

-- The element at the node's position is the node's.
0 indexAtNode : (xs : Vect m a) -> (x : a) -> (ys : Vect k a) -> (pos : Fin (m + S k)) -> finToNat pos = m ->
                Vect.index pos (xs ++ x :: ys) = x
indexAtNode [] x ys FZ _ = Refl
indexAtNode [] x ys (FS pos) same = void (SIsNotZ same)
indexAtNode (z :: xs) x ys FZ same = void (SIsNotZ (sym same))
indexAtNode (z :: xs) x ys (FS pos) same = indexAtNode xs x ys pos (unS same)

-- The element at a position past the node is the part after's, at the
-- position numbered as far past it.
0 indexAfter : (xs : Vect m a) -> (x : a) -> (ys : Vect k a) -> (pos : Fin (m + S k)) -> (f : Fin k) ->
               finToNat pos = m + S (finToNat f) -> Vect.index pos (xs ++ x :: ys) = Vect.index f ys
indexAfter [] x ys FZ f same = void (SIsNotZ (sym same))
indexAfter [] x ys (FS pos) f same = rewrite finToNatInjective pos f (unS same) in Refl
indexAfter (z :: xs) x ys FZ f same = void (SIsNotZ (sym same))
indexAfter (z :: xs) x ys (FS pos) f same = indexAfter xs x ys pos f (unS same)

-- A position past the node, and within the vector, is within the part
-- after.
0 pastBelow : (m, j : Nat) -> LT (m + S j) (m + S k) -> LT j k
pastBelow Z j lt = fromLteSucc lt
pastBelow (S m) j lt = pastBelow m j (fromLteSucc lt)

||| The element at a position, with the evidence that it is the vector's
||| there: at a node, read in the part before, at the node, or in the part
||| after, as the position's number compares with the part before's
||| length.
export
entryAt : {0 v : Vect n a} -> (pos : Fin n) -> Indexed v -> Subset a (\y => y = Vect.index pos v)
entryAt pos Bare = absurd pos
entryAt pos (Node m {xs} {k} {ys} l x r) = case placed m (finToNat pos) of
  Before below =>
    let (Element y same) = entryAt (natToFinLT (finToNat pos) {prf = below}) l in
    Element y (trans same (sym (indexBefore xs (x :: ys) pos (natToFinLT (finToNat pos) {prf = below})
                                            (finToNatLT (finToNat pos) {prf = below}))))
  AtNode here => Element x (sym (indexAtNode xs x ys pos here))
  After j past =>
    let 0 within := pastBelow m j (replace {p = \q => LT q (m + S k)} past (elemSmallerThanBound pos)) in
    let (Element y same) = entryAt (natToFinLT j {prf = within}) r in
    Element y (trans same (sym (indexAfter xs x ys pos (natToFinLT j {prf = within})
                                           (trans past (cong (\i => m + S i) (sym (finToNatLT j {prf = within})))))))

------------------------------------------------------------------------------
-- Making the tree
------------------------------------------------------------------------------

-- A length cut around a node: none, or m before the node and k after it.
data Halves : Nat -> Type where
  NoHalves : Halves Z
  HalvesAt : (m, k : Nat) -> Halves (m + S k)

-- One more on each side of the node.
0 widened : (m, k : Nat) -> S m + S (S k) = S (S (m + S k))
widened m k = cong S (sym (plusSuccRightSucc m (S k)))

-- A length cut around a node, the two sides within one of each other: two
-- less is cut so, and each side gains one.
halves : (n : Nat) -> Halves n
halves Z = NoHalves
halves (S Z) = HalvesAt Z Z
halves (S (S n)) = case halves n of
  NoHalves => HalvesAt (S Z) Z
  HalvesAt m k => replace {p = Halves} (widened m k) (HalvesAt (S m) (S k))

-- A vector m + 1 + k long, cut around its node.
data Cut : (m, k : Nat) -> Vect (m + S k) a -> Type where
  MkCut : (xs : Vect m a) -> (x : a) -> (ys : Vect k a) -> Cut m k (xs ++ x :: ys)

-- A vector cut after its first m elements.
cut : (m : Nat) -> {0 k : Nat} -> (v : Vect (m + S k) a) -> Cut m k v
cut Z (x :: ys) = MkCut [] x ys
cut (S m) (y :: v) = case cut m v of
  MkCut xs x ys => MkCut (y :: xs) x ys

-- Each side of a node is shorter than the whole.
0 beforeShorter : (m, k : Nat) -> LT m (m + S k)
beforeShorter m k = rewrite sym (plusSuccRightSucc m k) in LTESucc (lteAddRight m)

0 afterShorter : (m, k : Nat) -> LT k (m + S k)
afterShorter m k = rewrite plusCommutative m (S k) in LTESucc (lteAddRight k)

-- A vector of a length cut so, held as a tree: each side is shorter, the
-- measure it recurses on.
heldBy : {0 n : Nat} -> Halves n -> (v : Vect n a) -> (0 _ : Accessible LT n) -> Indexed v
heldBy NoHalves [] _ = Bare
heldBy (HalvesAt m k) v (Access rec) = case cut m v of
  MkCut xs x ys => Node m (heldBy (halves m) xs (rec m (beforeShorter m k))) x
                          (heldBy (halves k) ys (rec k (afterShorter m k)))

||| A vector held as a tree, made once, in as many steps as its length
||| times the tree's depth.
export
indexed : {n : Nat} -> (v : Vect n a) -> Indexed v
indexed v = heldBy (halves n) v (wellFounded n)
