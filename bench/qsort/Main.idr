-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
module Main

-- Quicksort of arrays of 32-bit words, n times over for every size below
-- n: Lean's `qsort.lean` (Counting Immutable Beans), where the array is a
-- pure value updated in place while unshared. Here it is a linear array
-- (Array's LArray), fresh for each size and threaded at quantity 1 through
-- every swap: pure code, each update in place. A position the sort
-- computes is checked against the size where it is used; the sort keeps
-- every one below it. Prints a checksum of the middle elements, so that
-- every language prints the same line.

import Prelude
import Linear.Notation
import Array

Arr : Nat -> Type
Arr n = LArray [<n] Bits32

-- The element at i, with the array given back (0 past the end).
get : {n : Nat} -> (1 _ : Arr n) -> Nat -> Res Bits32 (const (Arr n))
get a i = case checkIndex n i of
  Just j => read a [<j]
  Nothing => 0 # a

-- The array with v at i (unchanged past the end).
set : {n : Nat} -> (1 _ : Arr n) -> Nat -> Bits32 -> Arr n
set a i v = case checkIndex n i of
  Just j => write a [<j] v
  Nothing => a

badRand : Bits32 -> Bits32
badRand seed = seed * 1664525 + 1013904223

-- The array filled with pseudo-random words starting from seed.
fillRandom : {n : Nat} -> (1 _ : Arr n) -> Nat -> Bits32 -> Arr n
fillRandom a i s = if i < n then fillRandom (set a i s) (S i) (badRand s) else a

swap : {n : Nat} -> (1 _ : Arr n) -> Nat -> Nat -> Arr n
swap a i j =
  let x # a1 = get a i
      y # a2 = get a1 j
  in set (set a2 i y) j x

partitionAux : {n : Nat} -> (1 _ : Arr n) -> Nat -> Bits32 -> Nat -> Nat -> Res Nat (const (Arr n))
partitionAux a hi pivot i j =
  if j < hi then
    let x # a1 = get a j in
    if x < pivot
      then partitionAux (swap a1 i j) hi pivot (S i) (S j)
      else partitionAux a1 hi pivot i (S j)
  else i # swap a i hi

-- The median of three as the pivot, moved to the end; then the partition.
partition : {n : Nat} -> (1 _ : Arr n) -> Nat -> Nat -> Res Nat (const (Arr n))
partition a lo hi =
  let mid = (lo + hi) `div` 2
      am # a1 = get a mid
      al # a2 = get a1 lo
      1 a3 = if am < al then swap a2 lo mid else a2
      ah # a4 = get a3 hi
      al' # a5 = get a4 lo
      1 a6 = if ah < al' then swap a5 lo hi else a5
      am' # a7 = get a6 mid
      ah' # a8 = get a7 hi
      1 a9 = if am' < ah' then swap a8 mid hi else a8
      pivot # a10 = get a9 hi
  in partitionAux a10 hi pivot lo lo

qsortAux : {n : Nat} -> (1 _ : Arr n) -> Nat -> Nat -> Arr n
qsortAux a low high =
  if low < high then
    let mid # a1 = partition a low high
        1 a2 = qsortAux a1 low mid
    in qsortAux a2 (S mid) high
  else a

checkSorted : {n : Nat} -> (1 _ : Arr n) -> Nat -> Res Bool (const (Arr n))
checkSorted a i =
  if S i < n then
    let x # a1 = get a i
        y # a2 = get a1 (S i)
    in if x <= y then checkSorted a2 (S i) else False # a2
  else True # a

discard : (1 _ : Arr n) -> ()
discard a = let MkBang _ = freeze a in ()

-- Sorts an array of size i and gives its middle element, or -1 if the
-- result is not sorted.
one : Nat -> Int
one i =
  unrestricted $ withArray [<i] 0 (\fresh =>
    let 1 a = qsortAux (fillRandom fresh 0 (cast i)) 0 (pred i)
        ok # a1 = checkSorted a 0
    in if not ok then let () = discard a1 in MkBang (-1)
       else if i > 0 then let m # a2 = get a1 (i `div` 2) in let () = discard a2 in MkBang (cast m)
       else let () = discard a1 in MkBang 0)

-- Sorts arrays of every size i < n, and returns the sum of their middle
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
