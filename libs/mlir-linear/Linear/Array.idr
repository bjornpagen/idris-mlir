||| Mutable arrays, used linearly: one array object, threaded through every
||| read and write at quantity 1, so that each operation updates it in place
||| and no two references to it exist.
|||
||| An array is its size and its backing, base's array, whose first `size`
||| slots are its elements. The backing's length is the array's capacity,
||| kept nowhere else, so that no second count can drift from the cell's
||| length: `push` stores in place while the backing has room, and moves to
||| one at least twice as long when it has none. Every slot holds a value
||| from the start (`newArray` fills, and so does growth), so a read gives
||| the element, not a `Maybe` of it. An index outside the size is a crash,
||| as an index outside the backing is for base's primitive underneath, even
||| where the backing has a slot there.
|||
||| The array leaves the linear discipline only through `freeze`, after
||| which it is read-only and shared freely, and exactly its elements. A
||| continuation that creates an array returns an unrestricted value (`!*`),
||| so the array itself cannot escape it.
|||
||| In plain Idris over base's `Data.IOArray.Prims`; idris-mlir compiles
||| the array to its size beside one runtime cell, and each operation to a
||| load or a store.
module Linear.Array

import Data.IOArray.Prims
import Linear.Notation

%default total

||| The number of slots of a backing, which base's primitives do not give.
||| The spec is Chez's because bench/ also times these programs on Idris's
||| Chez backend, where the backing is a vector (and a Scheme foreign
||| function is passed its erased type argument too); idris-mlir gives it
||| the backing's length.
%foreign "scheme:(lambda (ty v) (vector-length v))"
prim__arraySize : forall a . ArrayData a -> Int

||| `i`, when it is at least 0 and below `n`; else the program crashes, as
||| at an index outside an array. Each index is checked with it against its
||| array's size, which is below the backing's length once the array has
||| grown. idris-mlir makes it the guard of an index against `n`
||| (`idr.check.in_bounds`), which its proofs erase as they erase an
||| access's own. Idris's Chez backend compiles at Chez's unsafe level,
||| where a `vector-ref` outside its vector is not checked, so the spec
||| raises the error itself.
%foreign "scheme:(lambda (i n) (if (and (<= 0 i) (< i n)) i (error #f \"array index out of bounds\")))"
prim__index : Int -> Int -> Int

------------------------------------------------------------------------------
-- Index spaces
------------------------------------------------------------------------------

-- The two loops over an array's index space, in plain Idris over the
-- primitives. idris-mlir knows these two by name: when the element (and a
-- fold's accumulator) is a machine word, an `Int`, a `Double`, a `Char` or
-- one of the fixed widths, each loop is one operation of its own, which it
-- lowers to a linalg operation over the array's memory, tiled and
-- vectorized; any other instance compiles as written. A fold reads a
-- frozen array, and a loop that makes an array makes a new one, linear:
-- the arrays it reads are frozen, so that its function may read them at
-- any index. Growing and trimming a backing are such loops too.

||| A new array of `n` elements, element `i` being `f i`: base's primitive
||| makes it of a fill, `f 0`, which is element 0, and `f i` is then written
||| at each index from 1 on. So `f` is applied once at each index, at 0
||| first, and at 0 even when `n` is not positive.
prim__generate : forall a . (n : Int) -> (Int -> a) -> PrimIO (ArrayData a)
prim__generate n f w =
  case prim__newArray (max 0 n) (f 0) w of
    -- The elements after the first, counted in Integer: as an Int, n - 1
    -- would wrap at the least Int, to the greatest.
    MkIORes arr w1 => go arr (integerToNat (cast n - 1)) 1 w1
  where
    go : ArrayData a -> Nat -> Int -> PrimIO (ArrayData a)
    go arr Z i w = MkIORes arr w
    go arr (S k) i w = case prim__arraySet arr i (f i) w of
      MkIORes _ w1 => go arr k (i + 1) w1

||| The elements folded from the left in index order, each with its index:
||| `f (f (f z 0 x0) 1 x1) 2 x2`.
prim__foldl : forall a, b . ArrayData a -> b -> (b -> Int -> a -> b) -> PrimIO b
prim__foldl arr z f w = go (integerToNat (cast (prim__arraySize arr))) 0 z w
  where
    go : Nat -> Int -> b -> PrimIO b
    go Z i acc w = MkIORes acc w
    go (S k) i acc w = case prim__arrayGet arr i w of
      MkIORes x w1 => go k (i + 1) (f acc i x) w1

------------------------------------------------------------------------------
-- Arrays
------------------------------------------------------------------------------

||| A mutable array of `a`, threaded linearly: its size and its backing,
||| whose first `size` slots are its elements and whose length is its
||| capacity, 0 <= size <= capacity. Only this module builds one, so only
||| it can break that.
export
data Array : Type -> Type where
  MkArray : Int -> ArrayData a -> Array a

||| An array frozen: read-only, and shared freely. Its backing is exactly
||| its elements, so that every read of it, and every loop over it, covers
||| the backing whole.
export
data IArray : Type -> Type where
  MkIArray : ArrayData a -> IArray a

||| The array of every slot of `arr`: its size is its capacity. Every array
||| that never grew is one.
whole : ArrayData a -> Array a
whole arr = MkArray (prim__arraySize arr) arr

||| A new array of `n` elements, each `x`; a non-positive `n` makes an
||| empty array. Bind it at quantity 1 (`let 1 a = mkArray n x`) and thread
||| it: every operation then updates the one object in place. Bound
||| unrestricted and shared, it is still that one object, as on every
||| backend.
export
mkArray : (n : Int) -> a -> Array a
mkArray n x = whole (unsafePerformIO (primIO (prim__newArray (max 0 n) x)))

||| A new array of `n` elements, each `x`, given to a continuation that
||| returns an unrestricted value, so that the array cannot leave it.
export
newArray : (n : Int) -> a -> (1 k : Array a -@ !* b) -> b
newArray n x k = unrestricted (k (mkArray n x))

||| The element at `i`, with the array given back. Outside the size: a
||| crash.
export
read : (1 _ : Array a) -> Int -> Res a (const (Array a))
read (MkArray n arr) i = unsafePerformIO (primIO (prim__arrayGet arr (prim__index i n))) # MkArray n arr

||| The array with `x` at `i`. Outside the size: a crash. The array given
||| back comes out of the action, so that the write is never dropped as an
||| unused value.
export
write : (1 _ : Array a) -> Int -> a -> Array a
write (MkArray n arr) i x =
  unsafePerformIO (do primIO (prim__arraySet arr (prim__index i n) x); pure (MkArray n arr))

||| The element at `i` replaced by `f` of it, with the old element given
||| back. Outside the size: a crash.
export
modify : (1 _ : Array a) -> Int -> (a -> a) -> Res a (const (Array a))
modify arr i f = let x # arr' = read arr i in x # write arr' i (f x)

||| The number of elements, with the array given back.
export
size : (1 _ : Array a) -> Res Int (const (Array a))
size (MkArray n arr) = n # MkArray n arr

||| The number of elements the array holds before a push must grow it: its
||| backing's length, with the array given back.
export
capacity : (1 _ : Array a) -> Res Int (const (Array a))
capacity (MkArray n arr) = prim__arraySize arr # MkArray n arr

||| The greatest Int. A capacity asked past it is held to it, so that a
||| request never wraps to a smaller capacity.
greatest : Int
greatest = 9223372036854775807

||| The capacity a backing of `cap` slots grows to when `need` are needed:
||| at least double, so that n pushes copy fewer than 2n elements in all,
||| and at least 4, so that the first pushes onto an empty array do not each
||| copy.
grown : (cap, need : Int) -> Int
grown cap need = max need (max 4 (2 * cap))

||| A backing of `cap` slots, at least as many as `arr`'s: `arr`'s slots,
||| then `x` in each slot after them, each written once.
regrow : ArrayData a -> Int -> a -> ArrayData a
regrow arr cap x =
  unsafePerformIO (primIO (prim__generate cap (\j =>
    if j < prim__arraySize arr then unsafePerformIO (primIO (prim__arrayGet arr j)) else x)))

||| The array with `x` after its last element: stored in place while the
||| backing has room, which neither allocates nor changes a count; else
||| moved to a backing at least twice as long, whose new slots, the one
||| after the last element among them, hold `x`.
export
push : (1 _ : Array a) -> a -> Array a
push (MkArray n arr) x =
  if n < prim__arraySize arr
     then unsafePerformIO (do primIO (prim__arraySet arr n x); pure (MkArray (n + 1) arr))
     else MkArray (n + 1) (regrow arr (grown (prim__arraySize arr) (n + 1)) x)

||| The last element, taken off, with the array given back; `Nothing` when
||| the array is empty, which makes it the test of emptiness too. The
||| capacity stays, and the slot keeps the element until a push overwrites
||| it or the array goes: every value of `a` at hand is some live element,
||| so clearing the slot would only move a count from one element to
||| another, at the cost of a read and a store per pop.
export
pop : (1 _ : Array a) -> Res (Maybe a) (const (Array a))
pop (MkArray n arr) =
  if n > 0
     then Just (unsafePerformIO (primIO (prim__arrayGet arr (n - 1)))) # MkArray (n - 1) arr
     else Nothing # MkArray n arr

||| The array with room for `k` more elements than its size. When its
||| capacity is less, it moves to a backing at least twice as long, and as
||| long as the size and `k` together when that is more (held to the
||| greatest Int), whose new slots hold `x`: an empty array of no capacity
||| holds no value of `a` to fill them with, and only the caller can name
||| one. Otherwise, a `k` that is not positive included, the array is as it
||| was.
export
reserve : (1 _ : Array a) -> Int -> a -> Array a
reserve (MkArray n arr) k x =
  if k <= prim__arraySize arr - n
     then MkArray n arr
     else MkArray n (regrow arr (grown (prim__arraySize arr) (if k > greatest - n then greatest else n + k)) x)

||| The first `n` slots of `arr`, copied. `n` is below its length, so slot
||| 0, which generate reads first, exists even when `n` is 0.
trimmed : ArrayData a -> Int -> ArrayData a
trimmed arr n =
  unsafePerformIO (primIO (prim__generate n (\j => unsafePerformIO (primIO (prim__arrayGet arr j)))))

||| The array, frozen: the linear phase ends, and the continuation reads
||| exactly its elements as a shared value. A backing with room past the
||| size is copied to the size once; one without is the frozen array
||| itself, so freezing an array that never grew copies nothing.
export
freeze : (1 _ : Array a) -> (IArray a -> b) -> b
freeze (MkArray n arr) k = k (MkIArray (if n < prim__arraySize arr then trimmed arr n else arr))

||| The element of a frozen array at `i`. Out of bounds: a crash.
export
iread : IArray a -> Int -> a
iread (MkIArray arr) i = unsafePerformIO (primIO (prim__arrayGet arr i))

||| The number of elements of a frozen array.
export
isize : IArray a -> Int
isize (MkIArray arr) = prim__arraySize arr

------------------------------------------------------------------------------
-- Loops over arrays
------------------------------------------------------------------------------

||| A new array of `n` elements, element `i` being `f i`. A non-positive `n`
||| makes an empty array; `f 0` is applied first even then (it is the
||| fill base's primitive needs), so `f` must be defined at 0.
export
generate : (n : Int) -> (Int -> a) -> Array a
generate n f = whole (unsafePerformIO (primIO (prim__generate n f)))

||| The elements of a frozen array folded from the left in index order,
||| each with its index: `ifoldl f z` of `[x0, x1]` is `f (f z 0 x0) 1 x1`.
export
ifoldl : (acc -> Int -> a -> acc) -> acc -> IArray a -> acc
ifoldl f z (MkIArray arr) = unsafePerformIO (primIO (prim__foldl arr z f))

||| The elements of a frozen array folded from the left in index order:
||| `foldl f z` of `[x0, x1]` is `f (f z x0) x1`.
export
foldl : (acc -> a -> acc) -> acc -> IArray a -> acc
foldl f = ifoldl (\acc, _, x => f acc x)

||| The sum of a frozen array's elements, added from the left in index
||| order.
export
sum : Num a => IArray a -> a
sum = foldl (+) 0

||| A new array of `f i x` for each element `x` at `i` of a frozen array.
||| Its first element is read first (`generate`), so the array must not be
||| empty.
export
imap : (Int -> a -> b) -> IArray a -> Array b
imap f frozen = generate (isize frozen) (\i => f i (iread frozen i))

||| A new array of `f x` for each element `x` of a frozen array, which must
||| not be empty (`imap`).
export
map : (a -> b) -> IArray a -> Array b
map f = imap (\_, x => f x)

||| A new array of `f x y` for each pair of elements at one index of two
||| frozen arrays, as long as the shorter; neither may be empty (`imap`).
export
zipWith : (a -> b -> c) -> IArray a -> IArray b -> Array c
zipWith f xs ys = generate (min (isize xs) (isize ys)) (\i => f (iread xs i) (iread ys i))
