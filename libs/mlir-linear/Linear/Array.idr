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
