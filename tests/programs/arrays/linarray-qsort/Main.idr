module Main

-- Quicksort of arrays of 32-bit words, n times over for every size below
-- n: Lean's `qsort.lean` (Counting Immutable Beans), where the array is a
-- pure value updated in place while unshared. Here it is a growable linear
-- vector (Linear.Vec), fresh for each size and threaded at quantity 1
-- through every swap: pure code, each update in place. Prints a checksum
-- of the middle elements, so that every language prints the same line.

import Prelude
import Linear.Notation
import Array
import Linear.Vec

Arr : Type
Arr = Vec Bits32

badRand : Bits32 -> Bits32
badRand seed = seed * 1664525 + 1013904223

-- The vector filled with pseudo-random words starting from seed.
fillRandom : (1 _ : Arr) -> Nat -> Nat -> Bits32 -> Arr
fillRandom a n i s = if i < n then fillRandom (Vec.write a i s) n (S i) (badRand s) else a

swap : (1 _ : Arr) -> Nat -> Nat -> Arr
swap a i j =
  let x # a1 = Vec.read a i
      y # a2 = Vec.read a1 j
  in Vec.write (Vec.write a2 i y) j x

partitionAux : (1 _ : Arr) -> Nat -> Bits32 -> Nat -> Nat -> Res Nat (const Arr)
partitionAux a hi pivot i j =
  if j < hi then
    let x # a1 = Vec.read a j in
    if x < pivot
      then partitionAux (swap a1 i j) hi pivot (S i) (S j)
      else partitionAux a1 hi pivot i (S j)
  else i # swap a i hi

-- The median of three as the pivot, moved to the end; then the partition.
partition : (1 _ : Arr) -> Nat -> Nat -> Res Nat (const Arr)
partition a lo hi =
  let mid = (lo + hi) `div` 2
      am # a1 = Vec.read a mid
      al # a2 = Vec.read a1 lo
      1 a3 = if am < al then swap a2 lo mid else a2
      ah # a4 = Vec.read a3 hi
      al' # a5 = Vec.read a4 lo
      1 a6 = if ah < al' then swap a5 lo hi else a5
      am' # a7 = Vec.read a6 mid
      ah' # a8 = Vec.read a7 hi
      1 a9 = if am' < ah' then swap a8 mid hi else a8
      pivot # a10 = Vec.read a9 hi
  in partitionAux a10 hi pivot lo lo

qsortAux : (1 _ : Arr) -> Nat -> Nat -> Arr
qsortAux a low high =
  if low < high then
    let mid # a1 = partition a low high
        1 a2 = qsortAux a1 low mid
    in qsortAux a2 (S mid) high
  else a

checkSorted : (1 _ : Arr) -> Nat -> Nat -> Res Bool (const Arr)
checkSorted a n i =
  if S i < n then
    let x # a1 = Vec.read a i
        y # a2 = Vec.read a1 (S i)
    in if x <= y then checkSorted a2 n (S i) else False # a2
  else True # a

discard : (1 _ : Arr) -> ()
discard a = let MkBang _ = Vec.freeze a in ()

-- Sorts a vector of size i and gives its middle element, or -1 if the
-- result is not sorted.
one : Nat -> Int
one i =
  unrestricted $ withVec i 0 (\fresh =>
    let 1 a = qsortAux (fillRandom fresh i 0 (cast i)) 0 (pred i)
        ok # a1 = checkSorted a i 0
    in if not ok then let () = discard a1 in MkBang (-1)
       else if i > 0 then let m # a2 = Vec.read a1 (i `div` 2) in let () = discard a2 in MkBang (cast m)
       else let () = discard a1 in MkBang 0)

-- Sorts vectors of every size i < n, and returns the sum of their middle
-- elements, or -1 if one is not sorted.
sizes : Nat -> Nat -> Int -> Int
sizes n i acc =
  if i >= n then acc
  else let m = one i in if m < 0 then -1 else sizes n (S i) (acc + m)

reps : Nat -> Nat -> Int -> Int
reps n k acc =
  if k >= n then acc
  else let s = sizes n 0 0 in if s < 0 then -1 else reps n (S k) (acc + s)

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
  let s = reps (cast n) 0 0
  if s < 0 then putStrLn "array is not sorted" else printLn s
