||| Mutable arrays, used linearly: one array object, threaded through every
||| read and write at quantity 1, so that each operation updates it in place
||| and no two references to it exist. Every element holds a value from the
||| start (`newArray` fills), and an index out of bounds is a crash, as it
||| is for base's array primitive underneath, so a read gives the element,
||| not a `Maybe` of it.
|||
||| The array leaves the linear discipline only through `freeze`, after
||| which it is read-only and shared freely. A continuation that creates an
||| array returns an unrestricted value (`!*`), so the array itself cannot
||| escape it.
|||
||| In plain Idris over base's `Data.IOArray.Prims`, which every backend
||| implements, so the stock Chez backend runs the same program; idris-mlir
||| compiles the array to one runtime cell and each operation to a load or
||| a store.
module Linear.Array

import Data.IOArray.Prims
import Linear.Notation

%default total

||| The number of elements, which every backend keeps with the array: on
||| Chez the array is a vector (and a Scheme foreign function is passed its
||| erased type argument too), and idris-mlir gives this spec the array's
||| dimension.
%foreign "scheme:(lambda (ty v) (vector-length v))"
prim__arraySize : forall a . ArrayData a -> Int

||| A mutable array of `a`, threaded linearly.
export
data Array : Type -> Type where
  MkArray : ArrayData a -> Array a

||| An array frozen: read-only, and shared freely.
export
data IArray : Type -> Type where
  MkIArray : ArrayData a -> IArray a

||| A new array of `n` elements, each `x`; a non-positive `n` makes an
||| empty array. Bind it at quantity 1 (`let 1 a = mkArray n x`) and thread
||| it: every operation then updates the one object in place. Bound
||| unrestricted and shared, it is still that one object, as on every
||| backend.
export
mkArray : (n : Int) -> a -> Array a
mkArray n x = MkArray (unsafePerformIO (primIO (prim__newArray (max 0 n) x)))

||| A new array of `n` elements, each `x`, given to a continuation that
||| returns an unrestricted value, so that the array cannot leave it.
export
newArray : (n : Int) -> a -> (1 k : Array a -@ !* b) -> b
newArray n x k = unrestricted (k (mkArray n x))

||| The element at `i`, with the array given back. Out of bounds: a crash.
export
read : (1 _ : Array a) -> Int -> Res a (const (Array a))
read (MkArray arr) i = unsafePerformIO (primIO (prim__arrayGet arr i)) # MkArray arr

||| The array with `x` at `i`. Out of bounds: a crash. The array given
||| back comes out of the action, so that the write is never dropped as an
||| unused value.
export
write : (1 _ : Array a) -> Int -> a -> Array a
write (MkArray arr) i x = unsafePerformIO (do primIO (prim__arraySet arr i x); pure (MkArray arr))

||| The element at `i` replaced by `f` of it, with the old element given
||| back. Out of bounds: a crash.
export
modify : (1 _ : Array a) -> Int -> (a -> a) -> Res a (const (Array a))
modify arr i f = let x # arr' = read arr i in x # write arr' i (f x)

||| The number of elements, with the array given back.
export
size : (1 _ : Array a) -> Res Int (const (Array a))
size (MkArray arr) = prim__arraySize arr # MkArray arr

||| The array, frozen: the linear phase ends, and the continuation reads
||| it as a shared value.
export
freeze : (1 _ : Array a) -> (IArray a -> b) -> b
freeze (MkArray arr) k = k (MkIArray arr)

||| The element of a frozen array at `i`. Out of bounds: a crash.
export
iread : IArray a -> Int -> a
iread (MkIArray arr) i = unsafePerformIO (primIO (prim__arrayGet arr i))

||| The number of elements of a frozen array.
export
isize : IArray a -> Int
isize (MkIArray arr) = prim__arraySize arr

------------------------------------------------------------------------------
-- Index spaces
------------------------------------------------------------------------------

-- The two loops over an array's index space, in plain Idris over the
-- primitives, which every backend runs as written. idris-mlir knows these
-- two by name: when the element (and a fold's accumulator) is a machine
-- word, an `Int`, a `Double`, a `Char` or one of the fixed widths, each
-- loop is one operation of its own, which it lowers to a linalg
-- operation over the array's memory, tiled and vectorized; any other
-- instance compiles as written. A fold reads a frozen array, and a loop
-- that makes an array makes a new one, linear: the arrays it reads are
-- frozen, so that its function may read them at any index.

||| A new array of `n` elements, element `i` being `f i`: base's primitive
||| makes it of a fill, `f 0`, which is element 0, and `f i` is then written
||| at each index from 1 on. So `f` is applied once at each index, at 0
||| first, and at 0 even when `n` is not positive.
prim__generate : forall a . (n : Int) -> (Int -> a) -> PrimIO (ArrayData a)
prim__generate n f w =
  case prim__newArray (max 0 n) (f 0) w of
    MkIORes arr w1 => go arr (integerToNat (cast (n - 1))) 1 w1
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

||| A new array of `n` elements, element `i` being `f i`. A non-positive `n`
||| makes an empty array; `f 0` is applied first even then (it is the
||| fill base's primitive needs), so `f` must be defined at 0.
export
generate : (n : Int) -> (Int -> a) -> Array a
generate n f = MkArray (unsafePerformIO (primIO (prim__generate n f)))

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
