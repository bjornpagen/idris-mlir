module Main

-- Quicksort of arrays of 32-bit words, n times over for every size below
-- n: Lean's `qsort.lean` (Counting Immutable Beans), where the array is a
-- pure value updated in place while unshared. Here it is a growable linear
-- vector (Linear.Vec), fresh for each size and threaded at quantity 1
-- through every swap: pure code, each update in place. Prints a checksum
-- of the middle elements, so that every language prints the same line. A
-- position the partition computes is compared with the size where it is
-- used; one past the end, which the partition never gives, reads 0 and
-- swaps nothing.

import Prelude
import Data.So
import Linear.Notation
import Array
import Linear.Vec

Arr : Nat -> Type
Arr n = Vec n Bits32

-- The element at `i`; 0 past the end.
readAt : {n : Nat} -> (1 _ : Arr n) -> Nat -> Res Bits32 (const (Arr n))
readAt a i = case choose (i < n) of
  Left inside => Vec.read a (natToFinLt i @{inside})
  Right _ => 0 # a

badRand : Bits32 -> Bits32
badRand seed = seed * 1664525 + 1013904223

-- The vector filled with pseudo-random words starting from seed.
fillRandom : {n : Nat} -> (1 _ : Arr n) -> Nat -> Bits32 -> Arr n
fillRandom a i s = case choose (i < n) of
  Left inside => fillRandom (Vec.write a (natToFinLt i @{inside}) s) (S i) (badRand s)
  Right _ => a

swap : {n : Nat} -> (1 _ : Arr n) -> Nat -> Nat -> Arr n
swap a i j = case choose (i < n) of
  Left iIn => case choose (j < n) of
    Left jIn =>
      let at = natToFinLt i @{iIn}
          to = natToFinLt j @{jIn}
          x # a1 = Vec.read a at
          y # a2 = Vec.read a1 to
      in Vec.write (Vec.write a2 at y) to x
    Right _ => a
  Right _ => a

partitionAux : {n : Nat} -> (1 _ : Arr n) -> Nat -> Bits32 -> Nat -> Nat -> Res Nat (const (Arr n))
partitionAux a hi pivot i j =
  if j < hi then
    let x # a1 = readAt a j in
    if x < pivot
      then partitionAux (swap a1 i j) hi pivot (S i) (S j)
      else partitionAux a1 hi pivot i (S j)
  else i # swap a i hi

-- The median of three as the pivot, moved to the end; then the partition.
partition : {n : Nat} -> (1 _ : Arr n) -> Nat -> Nat -> Res Nat (const (Arr n))
partition a lo hi =
  let mid = (lo + hi) `div` 2
      am # a1 = readAt a mid
      al # a2 = readAt a1 lo
      1 a3 = if am < al then swap a2 lo mid else a2
      ah # a4 = readAt a3 hi
      al' # a5 = readAt a4 lo
      1 a6 = if ah < al' then swap a5 lo hi else a5
      am' # a7 = readAt a6 mid
      ah' # a8 = readAt a7 hi
      1 a9 = if am' < ah' then swap a8 mid hi else a8
      pivot # a10 = readAt a9 hi
  in partitionAux a10 hi pivot lo lo

qsortAux : {n : Nat} -> (1 _ : Arr n) -> Nat -> Nat -> Arr n
qsortAux a low high =
  if low < high then
    let mid # a1 = partition a low high
        1 a2 = qsortAux a1 low mid
    in qsortAux a2 (S mid) high
  else a

checkSorted : {n : Nat} -> (1 _ : Arr n) -> Nat -> Res Bool (const (Arr n))
checkSorted a i = case choose (S i < n) of
  Left inside =>
    let 0 next = ltOpReflectsLT (S i) n inside
        x # a1 = Vec.read a (natToFinLT i {prf = lteSuccLeft next})
        y # a2 = Vec.read a1 (natToFinLT (S i) {prf = next})
    in if x <= y then checkSorted a2 (S i) else False # a2
  Right _ => True # a

discard : (1 _ : Arr n) -> ()
discard a = let MkBang _ = Vec.freeze a in ()

-- Sorts a vector of size i and gives its middle element, or -1 if the
-- result is not sorted.
one : Nat -> Int
one i =
  unrestricted $ withVec i 0 (\fresh =>
    let 1 a = qsortAux (fillRandom fresh 0 (cast i)) 0 (pred i)
        ok # a1 = checkSorted a 0
    in if not ok then let () = discard a1 in MkBang (-1)
       else case choose (i `div` 2 < i) of
         Left inside => let m # a2 = Vec.read a1 (natToFinLt (i `div` 2) @{inside}) in let () = discard a2 in MkBang (cast m)
         Right _ => let () = discard a1 in MkBang 0)

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
