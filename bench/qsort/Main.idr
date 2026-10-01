module Main

-- Quicksort of arrays of 32-bit words, n times over for every size below
-- n: Lean's `qsort.lean` (Counting Immutable Beans), where the array is a
-- pure value updated in place while unshared. Here it is a linear array
-- (Linear.Array), threaded at quantity 1 through every swap: pure code,
-- each update in place. Prints a checksum of the middle elements, so that
-- every language prints the same line.

import Prelude
import Linear.Notation
import Linear.Array

Arr : Type
Arr = Array Bits32

badRand : Bits32 -> Bits32
badRand seed = seed * 1664525 + 1013904223

-- An array of n pseudo-random words starting from seed.
mkRandomArray : Int -> Bits32 -> Arr
mkRandomArray n seed = fill (mkArray n 0) 0 seed
  where
    fill : (1 _ : Arr) -> Int -> Bits32 -> Arr
    fill a i s = if i < n then fill (write a i s) (i + 1) (badRand s) else a

swap : (1 _ : Arr) -> Int -> Int -> Arr
swap a i j =
  let x # a1 = read a i
      y # a2 = read a1 j
  in write (write a2 i y) j x

partitionAux : (1 _ : Arr) -> Int -> Bits32 -> Int -> Int -> Res Int (const Arr)
partitionAux a hi pivot i j =
  if j < hi then
    let x # a1 = read a j in
    if x < pivot
      then partitionAux (swap a1 i j) hi pivot (i + 1) (j + 1)
      else partitionAux a1 hi pivot i (j + 1)
  else i # swap a i hi

-- The median of three as the pivot, moved to the end; then the partition.
partition : (1 _ : Arr) -> Int -> Int -> Res Int (const Arr)
partition a lo hi =
  let mid = (lo + hi) `div` 2
      am # a1 = read a mid
      al # a2 = read a1 lo
      1 a3 = if am < al then swap a2 lo mid else a2
      ah # a4 = read a3 hi
      al' # a5 = read a4 lo
      1 a6 = if ah < al' then swap a5 lo hi else a5
      am' # a7 = read a6 mid
      ah' # a8 = read a7 hi
      1 a9 = if am' < ah' then swap a8 mid hi else a8
      pivot # a10 = read a9 hi
  in partitionAux a10 hi pivot lo lo

qsortAux : (1 _ : Arr) -> Int -> Int -> Arr
qsortAux a low high =
  if low < high then
    let mid # a1 = partition a low high
        1 a2 = qsortAux a1 low mid
    in qsortAux a2 (mid + 1) high
  else a

checkSorted : (1 _ : Arr) -> Int -> Int -> Res Bool (const Arr)
checkSorted a n i =
  if i < n - 1 then
    let x # a1 = read a i
        y # a2 = read a1 (i + 1)
    in if x <= y then checkSorted a2 n (i + 1) else False # a2
  else True # a

discard : (1 _ : Arr) -> ()
discard a = freeze a (\_ => ())

-- Sorts the array of size i and gives its middle element, or -1 if the
-- result is not sorted.
one : Int -> Int
one i =
  let 1 a = qsortAux (mkRandomArray i (cast i)) 0 (i - 1)
      ok # a1 = checkSorted a i 0
  in if not ok then let () = discard a1 in -1
     else if i > 0 then let m # a2 = read a1 (i `div` 2) in let () = discard a2 in cast m
     else let () = discard a1 in 0

-- Sorts arrays of every size i < n, and returns the sum of their middle
-- elements, or -1 if one is not sorted.
sizes : Int -> Int -> Int -> Int
sizes n i acc =
  if i >= n then acc
  else let m = one i in if m < 0 then -1 else sizes n (i + 1) (acc + m)

reps : Int -> Int -> Int -> Int
reps n k acc =
  if k >= n then acc
  else let s = sizes n 0 0 in if s < 0 then -1 else reps n (k + 1) (acc + s)

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
  let s = reps n 0 0
  if s < 0 then putStrLn "array is not sorted" else printLn s
