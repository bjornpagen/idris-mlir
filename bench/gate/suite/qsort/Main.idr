module Main

-- Quicksort of arrays of 32-bit words, n times over for every size below
-- n. Lean's `qsort.lean` (Counting Immutable Beans), where the array is a
-- pure value updated in place while unshared; here it is base's array
-- primitive, which every backend implements. Lean
-- checks that each array is sorted; this version also prints a checksum of
-- the middle elements, so that every language prints the same line.

import Prelude
import Data.IOArray.Prims

Arr : Type
Arr = ArrayData Bits32

get : Arr -> Int -> IO Bits32
get a i = primIO (prim__arrayGet a i)

set : Arr -> Int -> Bits32 -> IO ()
set a i x = primIO (prim__arraySet a i x)

badRand : Bits32 -> Bits32
badRand seed = seed * 1664525 + 1013904223

-- An array of n pseudo-random words starting from seed.
mkRandomArray : Int -> Bits32 -> IO Arr
mkRandomArray n seed = do
    a <- primIO (prim__newArray n 0)
    fill a 0 seed
    pure a
  where
    fill : Arr -> Int -> Bits32 -> IO ()
    fill a i s = if i < n then do set a i s; fill a (i + 1) (badRand s) else pure ()

swap : Arr -> Int -> Int -> IO ()
swap a i j = do
  x <- get a i
  y <- get a j
  set a i y
  set a j x

partitionAux : Arr -> Int -> Bits32 -> Int -> Int -> IO Int
partitionAux a hi pivot i j =
  if j < hi then do
    x <- get a j
    if x < pivot
      then do swap a i j; partitionAux a hi pivot (i + 1) (j + 1)
      else partitionAux a hi pivot i (j + 1)
  else do
    swap a i hi
    pure i

partition : Arr -> Int -> Int -> IO Int
partition a lo hi = do
  let mid = (lo + hi) `div` 2
  am <- get a mid
  al <- get a lo
  if am < al then swap a lo mid else pure ()
  ah <- get a hi
  al <- get a lo
  if ah < al then swap a lo hi else pure ()
  am <- get a mid
  ah <- get a hi
  if am < ah then swap a mid hi else pure ()
  pivot <- get a hi
  partitionAux a hi pivot lo lo

qsortAux : Arr -> Int -> Int -> IO ()
qsortAux a low high =
  if low < high then do
    mid <- partition a low high
    qsortAux a low mid
    qsortAux a (mid + 1) high
  else pure ()

checkSorted : Arr -> Int -> Int -> IO Bool
checkSorted a n i =
  if i < n - 1 then do
    x <- get a i
    y <- get a (i + 1)
    if x <= y then checkSorted a n (i + 1) else pure False
  else pure True

-- Sorts arrays of every size i < n, and returns the sum of their middle
-- elements, or -1 if one is not sorted.
sizes : Int -> Int -> Int -> IO Int
sizes n i acc =
  if i >= n then pure acc
  else do
    a <- mkRandomArray i (cast i)
    qsortAux a 0 (i - 1)
    ok <- checkSorted a i 0
    if not ok then pure (-1) else do
      m <- if i > 0 then get a (i `div` 2) else pure 0
      sizes n (i + 1) (acc + cast m)

reps : Int -> Int -> Int -> IO Int
reps n k acc =
  if k >= n then pure acc
  else do
    s <- sizes n 0 0
    if s < 0 then pure (-1) else reps n (k + 1) (acc + s)

readInt : IO Int
readInt = go 0
  where
    go : Int -> IO Int
    go acc = do
      c <- getChar
      if isDigit c then go (acc * 10 + cast (ord c - 48)) else pure acc

main : IO ()
main = do
  n <- readInt
  s <- reps n 0 0
  if s < 0 then putStrLn "array is not sorted" else printLn s
