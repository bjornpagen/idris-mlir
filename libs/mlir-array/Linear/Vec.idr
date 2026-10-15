-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| A growable linear array: a linear array and how many of its leading
||| elements are the vector's, that number in the vector's type.
|||
||| The capacity is the linear array's extent, held there alone, so that no
||| second count can drift from it. A push stores in place while there is
||| room, and moves to an array at least twice as long, and at least 4,
||| when there is none: `n` pushes copy fewer than `2n` elements. Every slot
||| holds a value from the start, so a read gives the element, not a
||| `Maybe` of it.
|||
||| The size is the type's index, so a position is a `Fin` of it and a pop
||| takes a vector that has an element: no index is outside the vector and
||| no pop meets an empty one. A natural index is the caller's to check
||| (`Array.checkIndex`), and the caller says what a position outside means.
||| How many elements a loop pushes may depend on data: such a loop gives
||| back the size with the vector, `Res Nat (\n => Vec n a)`.
|||
||| A slot past the size holds the vector's fill, the value it was made
||| with, and never an element: a pop puts the fill back where the element
||| was, and a growth fills its new slots with it. So an element leaves the
||| vector with no reference to it left behind, and a slot is never unset.
module Linear.Vec

import Array
import Data.Fin.Properties
import Data.Nat
import Data.So
import Linear.Notation

%default total

||| A vector of `n` elements, at the front of a linear array of `cap`, the
||| fill in every slot after them, the proof that they fit erased. The size
||| is held as the index it is, so that `size` and a match on it read it.
export
data Vec : Nat -> Type -> Type where
  MkVec : {0 cap : Nat} -> (n : Nat) -> (0 fits : LTE n cap) -> (fill : a) ->
          (1 cells : LArray [<cap] a) -> Vec n a

||| A vector of `n` elements, each `v`, with room for exactly them and `v`
||| for its fill, given to a continuation as `withArray` gives an array:
||| used once, its result unrestricted, so that the vector cannot leave it
||| but by `freeze`.
export
withVec : (n : Nat) -> a -> (1 _ : (1 _ : Vec n a) -> !* b) -> !* b
withVec n v k = withArray [<n] v (\cells => k (MkVec n reflexive v cells))

||| The number of elements, with the vector given back.
export
size : (1 _ : Vec n a) -> Res Nat (const (Vec n a))
size (MkVec n fits v cells) = n # MkVec n fits v cells

||| How many elements the vector holds before a push must grow it, with
||| the vector given back.
export
capacity : (1 _ : Vec n a) -> Res Nat (const (Vec n a))
capacity (MkVec n fits v cells) = let [<c] # cells = LArray.shape cells in c # MkVec n fits v cells

||| An element's position as the slot of the cells that holds it: the same
||| number, below the capacity since the elements fit.
slot : Fin n -> (0 fits : LTE n cap) -> Index [<cap]
slot i fits = [<natToFinLT (finToNat i) {prf = transitive (elemSmallerThanBound i) fits}]

||| The element at `i`, with the vector given back.
export
read : (1 _ : Vec n a) -> Fin n -> Res a (const (Vec n a))
read (MkVec n fits v cells) i = let x # cells = LArray.read cells (slot i fits) in x # MkVec n fits v cells

||| The vector with `x` at `i`, in place.
export
write : (1 _ : Vec n a) -> Fin n -> a -> Vec n a
write (MkVec n fits v cells) i x = MkVec n fits v (LArray.write cells (slot i fits) x)

||| How many slots a full vector of capacity `c` grows by: to 4 when it is
||| below 2, else to twice `c`, and always by at least one, which the type
||| says.
extra : Nat -> Nat
extra c = S (minus (max 4 (2 * c)) (S c))

||| One more element fits once a vector of capacity `c` grows by a
||| successor.
0 oneMore : LTE n c -> LTE (S n) (c + S m)
oneMore fits = transitive (LTESucc fits)
  (rewrite sym (plusSuccRightSucc c m) in LTESucc (lteAddRight c))

||| The vector with `x` after its last element: stored in place while the
||| array has room; else the array grows, its new slots holding the fill,
||| and since the vector was full, the first of them, after its last
||| element, takes `x`.
export
push : (1 _ : Vec n a) -> a -> Vec (S n) a
push (MkVec n fits v cells) x =
  let [<c] # cells = LArray.shape cells in
  case choose (n < c) of
    Left below =>
      MkVec (S n) (ltOpReflectsLT n c below) v
        (LArray.write cells [<natToFinLT n {prf = ltOpReflectsLT n c below}] x)
    Right _ =>
      MkVec (S n) (oneMore fits) v
        (LArray.write (grow (extra c) v cells) [<natToFinLT n {prf = oneMore fits}] x)

||| The last element, taken off, with the vector given back. The capacity
||| stays, and the slot takes the fill back, so the vector keeps no
||| reference to the element it gave.
export
pop : (1 _ : Vec (S n) a) -> Res a (const (Vec n a))
pop (MkVec (S n) fits v cells) =
  let x # cells = LArray.read cells [<natToFinLT n {prf = fits}] in
  x # MkVec n (lteSuccLeft fits) v (LArray.write cells [<natToFinLT n {prf = fits}] v)

||| The vector with room for `k` more elements than its size. When it has
||| less, the array grows to at least twice its capacity, and to the size
||| and `k` together when that is more, the new slots holding the fill.
||| Otherwise the vector is as it was.
export
reserve : (1 _ : Vec n a) -> Nat -> Vec n a
reserve (MkVec n fits v cells) k =
  let [<c] # cells = LArray.shape cells in
  if k <= minus c n then MkVec n fits v cells
  else MkVec n (transitive fits (lteAddRight c)) v
         (grow (minus (max (n + k) (max 4 (2 * c))) c) v cells)

||| The elements, frozen: the linear phase ends.
export
freeze : (1 _ : Vec n a) -> !* (Vector n a)
freeze (MkVec n fits _ cells) = let MkBang arr = LArray.freeze cells in MkBang (take n @{fits} arr)
