-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| A growable linear array: a linear array and how many of its leading
||| elements are the vector's.
|||
||| The capacity is the linear array's extent, held there alone, so that no
||| second count can drift from it. A push stores in place while there is
||| room, and moves to an array at least twice as long, and at least 4,
||| when there is none: `n` pushes copy fewer than `2n` elements. Every slot
||| holds a value from the start, so a read gives the element, not a
||| `Maybe` of it. An index outside the size ends the program, as an index
||| outside an array would.
|||
||| A slot past the size holds the vector's fill, the value it was made
||| with, and never an element: a pop puts the fill back where the element
||| was, and a growth fills its new slots with it. So an element leaves the
||| vector with no reference to it left behind, and a slot is never unset.
module Linear.Vec

import Array
import Data.Nat
import Data.So
import Linear.Notation

%default total

||| A vector: `size` elements at the front of a linear array of `cap`, the
||| fill in every slot after them, the proof that they fit erased.
export
data Vec : Type -> Type where
  MkVec : {0 cap : Nat} -> (size : Nat) -> (0 fits : LTE size cap) -> (fill : a) ->
          (1 cells : LArray [<cap] a) -> Vec a

||| A vector of `n` elements, each `v`, with room for exactly them and `v`
||| for its fill, given to a continuation as `withArray` gives an array:
||| used once, its result unrestricted, so that the vector cannot leave it
||| but by `freeze`.
export
withVec : (n : Nat) -> a -> (1 _ : (1 _ : Vec a) -> !* b) -> !* b
withVec n v k = withArray [<n] v (\cells => k (MkVec n reflexive v cells))

||| The number of elements, with the vector given back.
export
size : (1 _ : Vec a) -> Res Nat (const (Vec a))
size (MkVec n fits v cells) = n # MkVec n fits v cells

||| How many elements the vector holds before a push must grow it, with
||| the vector given back.
export
capacity : (1 _ : Vec a) -> Res Nat (const (Vec a))
capacity (MkVec n fits v cells) = let [<c] # cells = LArray.shape cells in c # MkVec n fits v cells

||| The vector consumed, then the program ended as at an index outside an
||| array. Ending the program is total: it returns nothing that a caller
||| could go on with.
outOfBounds : (1 _ : Vec a) -> b
outOfBounds (MkVec _ _ _ cells) =
  let MkBang _ = LArray.freeze cells in assert_total (idris_crash "array index out of bounds")

||| The element at `i`, with the vector given back. Outside the size: the
||| program ends.
export
read : (1 _ : Vec a) -> Nat -> Res a (const (Vec a))
read (MkVec n fits v cells) i = case choose (i < n) of
  Left below =>
    let x # cells = LArray.read cells [<natToFinLT i {prf = transitive (ltOpReflectsLT i n below) fits}]
    in x # MkVec n fits v cells
  Right _ => outOfBounds (MkVec n fits v cells)

||| The vector with `x` at `i`, in place. Outside the size: the program
||| ends.
export
write : (1 _ : Vec a) -> Nat -> a -> Vec a
write (MkVec n fits v cells) i x = case choose (i < n) of
  Left below =>
    MkVec n fits v (LArray.write cells [<natToFinLT i {prf = transitive (ltOpReflectsLT i n below) fits}] x)
  Right _ => outOfBounds (MkVec n fits v cells)

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
push : (1 _ : Vec a) -> a -> Vec a
push (MkVec n fits v cells) x =
  let [<c] # cells = LArray.shape cells in
  case choose (n < c) of
    Left below =>
      MkVec (S n) (ltOpReflectsLT n c below) v
        (LArray.write cells [<natToFinLT n {prf = ltOpReflectsLT n c below}] x)
    Right _ =>
      MkVec (S n) (oneMore fits) v
        (LArray.write (grow (extra c) v cells) [<natToFinLT n {prf = oneMore fits}] x)

||| The last element, taken off, with the vector given back; `Nothing` when
||| it is empty. The capacity stays, and the slot takes the fill back, so
||| the vector keeps no reference to the element it gave.
export
pop : (1 _ : Vec a) -> Res (Maybe a) (const (Vec a))
pop (MkVec Z fits v cells) = Nothing # MkVec Z fits v cells
pop (MkVec (S k) fits v cells) =
  let x # cells = LArray.read cells [<natToFinLT k {prf = fits}] in
  Just x # MkVec k (lteSuccLeft fits) v (LArray.write cells [<natToFinLT k {prf = fits}] v)

||| The vector with room for `k` more elements than its size. When it has
||| less, the array grows to at least twice its capacity, and to the size
||| and `k` together when that is more, the new slots holding the fill.
||| Otherwise the vector is as it was.
export
reserve : (1 _ : Vec a) -> Nat -> Vec a
reserve (MkVec n fits v cells) k =
  let [<c] # cells = LArray.shape cells in
  if k <= minus c n then MkVec n fits v cells
  else MkVec n (transitive fits (lteAddRight c)) v
         (grow (minus (max (n + k) (max 4 (2 * c))) c) v cells)

||| The elements, frozen, with their number: the linear phase ends.
export
freeze : (1 _ : Vec a) -> !* (n : Nat ** Vector n a)
freeze (MkVec n fits _ cells) = let MkBang arr = LArray.freeze cells in MkBang (n ** take n @{fits} arr)
