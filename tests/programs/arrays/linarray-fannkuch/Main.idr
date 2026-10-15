module Main

-- fannkuch-redux (the Benchmarks Game) in pure code over growable linear
-- vectors (Linear.Vec): every permutation of 0..n-1, the number of prefix
-- reversals that brings 0 to the front, the largest such count and an
-- alternating checksum. The permutation, its working copy and the counters
-- are vectors threaded through every read and write at quantity 1, so each
-- update is in place without an IO monad and with no bounds-check Maybe:
-- the same loops as the IOArray version, from functional code.

import Prelude
import Linear.Notation
import Array
import Linear.Vec

Arr : Type
Arr = Vec Int

-- perm1[i] := i.
iota : (1 _ : Arr) -> Nat -> Nat -> Arr
iota a n i = if i >= n then a else iota (Vec.write a i (cast i)) n (S i)

copy : (1 _ : Arr) -> (1 _ : Arr) -> Nat -> Nat -> LPair Arr Arr
copy from to n i =
  if i >= n then from # to
  else let v # from' = Vec.read from i in copy from' (Vec.write to i v) n (S i)

-- Reverses perm[i..j].
rev : (1 _ : Arr) -> Nat -> Nat -> Arr
rev p i j =
  if i >= j then p
  else let a # p1 = Vec.read p i
           b # p2 = Vec.read p1 j
       in rev (Vec.write (Vec.write p2 i b) j a) (S i) (pred j)

-- The number of prefix reversals (each of perm[0..perm[0]]) that brings 0
-- to the front.
flips : (1 _ : Arr) -> Int -> Res Int (const Arr)
flips p k =
  let h # p1 = Vec.read p 0 in
  if h == 0 then k # p1 else flips (rev p1 0 (cast h)) (k + 1)

shift : (1 _ : Arr) -> Nat -> Nat -> Arr
shift p r i =
  if i >= r then p
  else let v # p1 = Vec.read p (S i) in shift (Vec.write p1 i v) r (S i)

-- Rotates perm1[0..r] left by one.
rotate : (1 _ : Arr) -> Nat -> Arr
rotate p r = let p0 # p1 = Vec.read p 0 in Vec.write (shift p1 r 0) r p0

-- The next permutation's r with the vectors, or the vectors when they are
-- exhausted.
data Next : Type where
  Done : (1 _ : Arr) -> (1 _ : Arr) -> Next
  More : Nat -> (1 _ : Arr) -> (1 _ : Arr) -> Next

next : Nat -> (1 _ : Arr) -> (1 _ : Arr) -> Nat -> Next
next n perm1 count r =
  if r == n then Done perm1 count
  else let perm1' = rotate perm1 r
           c # count1 = Vec.read count r
           count' = Vec.write count1 r (c - 1)
       in if c > 1 then More r perm1' count' else next n perm1' count' (S r)

-- count[i] := i + 1 for i below r.
counters : (1 _ : Arr) -> Nat -> Arr
counters count r = if r <= 1 then count else counters (Vec.write count (pred r) (cast r)) (pred r)

discard : (1 _ : Arr) -> ()
discard a = let MkBang _ = Vec.freeze a in ()

loop : Nat -> (1 _ : Arr) -> (1 _ : Arr) -> (1 _ : Arr) -> Nat -> Int -> Int -> Int -> !* (Int, Int)
loop n perm1 perm count r idx checksum maxf =
  let count1 = counters count r
      perm1' # perm' = copy perm1 perm n 0
      f # perm'' = flips perm' 0
      checksum' = if idx `mod` 2 == 0 then checksum + f else checksum - f
      maxf' = max maxf f
  in case next n perm1' count1 1 of
       Done a b => let () = discard a in let () = discard b in let () = discard perm'' in MkBang (checksum', maxf')
       More r' a b => loop n a perm'' b r' (idx + 1) checksum' maxf'

readInt : IO Int
readInt = go 0
  where
    go : Int -> IO Int
    go acc = do
      c <- getChar
      if isDigit c then go (acc * 10 + cast (ord c - 48)) else pure acc

-- The three vectors, each fresh at quantity 1 and threaded through the
-- loop.
run : Nat -> (Int, Int)
run n =
  unrestricted $
    withVec n (the Int 0) (\perm1 =>
      withVec n (the Int 0) (\perm =>
        withVec n (the Int 0) (\count =>
          loop n (iota perm1 n 0) perm count n 0 0 0)))

main : IO ()
main = do
  n <- readInt
  let (checksum, maxf) = run (cast n)
  printLn checksum
  putStrLn ("Pfannkuchen(" ++ show n ++ ") = " ++ show maxf)
