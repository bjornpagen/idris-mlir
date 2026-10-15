module Main

-- Bubble sort of a growable linear vector (linear-libs' benchmark 3):
-- every swap is two loads and two stores on the one vector, threaded at
-- quantity 1 through the passes, with no count changed and nothing
-- allocated.

import Prelude
import Linear.Notation
import Array
import Linear.Vec

Arr : Type
Arr = Vec Int

-- n pseudo-random numbers, written from index i on.
fill : (1 _ : Arr) -> Nat -> Nat -> Int -> Arr
fill a n i s = if i >= n then a else fill (Vec.write a i (s `mod` 1000)) n (S i) ((s * 1103515245 + 12345) `mod` 2147483648)

-- One pass: adjacent elements out of order are swapped; whether any were.
pass : (1 _ : Arr) -> Nat -> Nat -> Bool -> Res Bool (const Arr)
pass a n i swapped =
  if S i >= n then swapped # a
  else
    let x # a1 = Vec.read a i
        y # a2 = Vec.read a1 (S i)
    in if x > y then pass (Vec.write (Vec.write a2 i y) (S i) x) n (S i) True
       else pass a2 n (S i) swapped

bubble : (1 _ : Arr) -> Nat -> Arr
bubble a n =
  let swapped # a1 = pass a n 0 False
  in if swapped then bubble a1 n else a1

-- Whether the vector is sorted, and its checksum: the sum of each element
-- times its index.
check : (1 _ : Arr) -> Nat -> Nat -> Int -> Int -> Res (Bool, Int) (const Arr)
check a n i prev acc =
  if i >= n then (True, acc) # a
  else let x # a1 = Vec.read a i
       in if x < prev then (False, acc) # a1 else check a1 n (S i) x (acc + cast i * x)

run : Nat -> (Bool, Int)
run n = unrestricted $ withVec n (the Int 0) (\a =>
  let r # a1 = check (bubble (fill a n 0 42) n) n 0 0 0
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
