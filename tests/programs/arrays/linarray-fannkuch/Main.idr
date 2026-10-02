module Main

-- fannkuch-redux (the Benchmarks Game) in pure code over linear arrays
-- (Linear.Array): every permutation of 0..n-1, the number of prefix
-- reversals that brings 0 to the front, the largest such count and an
-- alternating checksum. The permutation, its working copy and the counters
-- are arrays threaded through every read and write at quantity 1, so each
-- update is in place without an IO monad, with no bounds-check Maybe, and
-- the compiler proves nothing is shared: the same loops as the IOArray
-- version, from functional code.

import Prelude
import Linear.Notation
import Linear.Array

Arr : Type
Arr = Array Int

-- perm1[i] := i.
iota : (1 _ : Arr) -> Int -> Int -> Arr
iota a n i = if i >= n then a else iota (write a i i) n (i + 1)

copy : (1 _ : Arr) -> (1 _ : Arr) -> Int -> Int -> LPair Arr Arr
copy from to n i =
  if i >= n then from # to
  else let v # from' = read from i in copy from' (write to i v) n (i + 1)

-- Reverses perm[i..j].
rev : (1 _ : Arr) -> Int -> Int -> Arr
rev p i j =
  if i >= j then p
  else let a # p1 = read p i
           b # p2 = read p1 j
       in rev (write (write p2 i b) j a) (i + 1) (j - 1)

-- The number of prefix reversals (each of perm[0..perm[0]]) that brings 0
-- to the front.
flips : (1 _ : Arr) -> Int -> Res Int (const Arr)
flips p k =
  let h # p1 = read p 0 in
  if h == 0 then k # p1 else flips (rev p1 0 h) (k + 1)

shift : (1 _ : Arr) -> Int -> Int -> Arr
shift p r i =
  if i >= r then p
  else let v # p1 = read p (i + 1) in shift (write p1 i v) r (i + 1)

-- Rotates perm1[0..r] left by one.
rotate : (1 _ : Arr) -> Int -> Arr
rotate p r = let p0 # p1 = read p 0 in write (shift p1 r 0) r p0

-- The next permutation's r with the arrays, or the arrays when they are
-- exhausted.
data Next : Type where
  Done : (1 _ : Arr) -> (1 _ : Arr) -> Next
  More : Int -> (1 _ : Arr) -> (1 _ : Arr) -> Next

next : Int -> (1 _ : Arr) -> (1 _ : Arr) -> Int -> Next
next n perm1 count r =
  if r == n then Done perm1 count
  else let perm1' = rotate perm1 r
           c # count1 = read count r
           count' = write count1 r (c - 1)
       in if c > 1 then More r perm1' count' else next n perm1' count' (r + 1)

-- count[i] := i + 1 for i below r.
fill : (1 _ : Arr) -> Int -> Arr
fill count r = if r <= 1 then count else fill (write count (r - 1) r) (r - 1)

discard : (1 _ : Arr) -> ()
discard a = freeze a (\_ => ())

loop : Int -> (1 _ : Arr) -> (1 _ : Arr) -> (1 _ : Arr) -> Int -> Int -> Int -> Int -> (Int, Int)
loop n perm1 perm count r idx checksum maxf =
  let count1 = fill count r
      perm1' # perm' = copy perm1 perm n 0
      f # perm'' = flips perm' 0
      checksum' = if idx `mod` 2 == 0 then checksum + f else checksum - f
      maxf' = max maxf f
  in case next n perm1' count1 1 of
       Done a b => let () = discard a in let () = discard b in let () = discard perm'' in (checksum', maxf')
       More r' a b => loop n a perm'' b r' (idx + 1) checksum' maxf'

readInt : IO Int
readInt = go 0
  where
    go : Int -> IO Int
    go acc = do
      c <- getChar
      if isDigit c then go (acc * 10 + cast (ord c - 48)) else pure acc

-- The three arrays, each bound at quantity 1 and threaded through the
-- loop.
run : Int -> (Int, Int)
run n =
  let 1 perm1 = mkArray n 0
      1 perm = mkArray n 0
      1 count = mkArray n 0
  in loop n (iota perm1 n 0) perm count n 0 0 0

main : IO ()
main = do
  n <- readInt
  let (checksum, maxf) = run n
  printLn checksum
  putStrLn ("Pfannkuchen(" ++ show n ++ ") = " ++ show maxf)
