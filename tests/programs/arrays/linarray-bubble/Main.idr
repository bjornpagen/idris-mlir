module Main

-- Bubble sort of a growable linear vector (linear-libs' benchmark 3):
-- every swap is two loads and two stores on the one vector, threaded at
-- quantity 1 through the passes, with no count changed and nothing
-- allocated. Each loop's test against the size gives the position it
-- reads, so no access is checked again.

import Prelude
import Data.Nat
import Data.So
import Linear.Notation
import Array
import Linear.Vec

Arr : Nat -> Type
Arr n = Vec n Int

-- n pseudo-random numbers, written from index i on.
fill : {n : Nat} -> (1 _ : Arr n) -> Nat -> Int -> Arr n
fill a i s = case choose (i < n) of
  Left inside => fill (Vec.write a (natToFinLt i @{inside}) (s `mod` 1000)) (S i) ((s * 1103515245 + 12345) `mod` 2147483648)
  Right _ => a

-- One pass: adjacent elements out of order are swapped; whether any were.
pass : {n : Nat} -> (1 _ : Arr n) -> Nat -> Bool -> Res Bool (const (Arr n))
pass a i swapped = case choose (S i < n) of
  Right _ => swapped # a
  Left inside =>
    let 0 next = ltOpReflectsLT (S i) n inside
        here = natToFinLT i {prf = lteSuccLeft next}
        there = natToFinLT (S i) {prf = next}
        x # a1 = Vec.read a here
        y # a2 = Vec.read a1 there
    in if x > y then pass (Vec.write (Vec.write a2 here y) there x) (S i) True
       else pass a2 (S i) swapped

bubble : {n : Nat} -> (1 _ : Arr n) -> Arr n
bubble a =
  let swapped # a1 = pass a 0 False
  in if swapped then bubble a1 else a1

-- Whether the vector is sorted, and its checksum: the sum of each element
-- times its index.
check : {n : Nat} -> (1 _ : Arr n) -> Nat -> Int -> Int -> Res (Bool, Int) (const (Arr n))
check a i prev acc = case choose (i < n) of
  Right _ => (True, acc) # a
  Left inside =>
    let x # a1 = Vec.read a (natToFinLt i @{inside})
    in if x < prev then (False, acc) # a1 else check a1 (S i) x (acc + cast i * x)

run : Nat -> (Bool, Int)
run n = unrestricted $ withVec n (the Int 0) (\a =>
  let r # a1 = check (bubble (fill a 0 42)) 0 0 0
      MkBang _ = Vec.freeze a1
  in MkBang r)

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
  let (sorted, sum) = run (cast n)
  putStrLn (if sorted then "sorted " ++ show sum else "not sorted")
