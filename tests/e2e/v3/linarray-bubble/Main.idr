module Main

-- Bubble sort of a linear array (linear-libs' benchmark 3): every swap is
-- two loads and two stores on the one array, threaded at quantity 1
-- through the passes, with no count changed and nothing allocated.

import Prelude
import Linear.Notation
import Linear.Array

Arr : Type
Arr = Array Int

-- An array of n pseudo-random numbers.
fill : (1 _ : Arr) -> Int -> Int -> Int -> Arr
fill a n i s = if i >= n then a else fill (write a i (s `mod` 1000)) n (i + 1) ((s * 1103515245 + 12345) `mod` 2147483648)

-- One pass: adjacent elements out of order are swapped; whether any were.
pass : (1 _ : Arr) -> Int -> Int -> Bool -> Res Bool (const Arr)
pass a n i swapped =
  if i + 1 >= n then swapped # a
  else
    let x # a1 = read a i
        y # a2 = read a1 (i + 1)
    in if x > y then pass (write (write a2 i y) (i + 1) x) n (i + 1) True
       else pass a2 n (i + 1) swapped

bubble : (1 _ : Arr) -> Int -> Arr
bubble a n =
  let swapped # a1 = pass a n 0 False
  in if swapped then bubble a1 n else a1

-- Whether the array is sorted, and its checksum: the sum of each element
-- times its index.
check : (1 _ : Arr) -> Int -> Int -> Int -> Int -> Res (Bool, Int) (const Arr)
check a n i prev acc =
  if i >= n then (True, acc) # a
  else let x # a1 = read a i
       in if x < prev then (False, acc) # a1 else check a1 n (i + 1) x (acc + i * x)

run : Int -> (Bool, Int)
run n =
  let 1 a = mkArray n 0
      r # a1 = check (bubble (fill a n 0 42) n) n 0 0 0
  in freeze a1 (\_ => r)

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
  let (sorted, sum) = run n
  putStrLn (if sorted then "sorted " ++ show sum else "not sorted")
