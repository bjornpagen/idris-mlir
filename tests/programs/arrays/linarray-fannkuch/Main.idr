module Main

-- fannkuch-redux (the Benchmarks Game) in pure code over growable linear
-- vectors (Linear.Vec): every permutation of 0..n-1, the number of prefix
-- reversals that brings 0 to the front, the largest such count and an
-- alternating checksum. The permutation, its working copy and the counters
-- are vectors threaded through every read and write at quantity 1, so each
-- update is in place without an IO monad and with no bounds-check Maybe:
-- the same loops as the IOArray version, from functional code. A position
-- the algorithm computes is compared with the size where it is used, and
-- one past the end, which a permutation of 0..n-1 never gives, reads 0 and
-- writes nothing.

import Prelude
import Data.So
import Linear.Notation
import Array
import Linear.Vec

Arr : Nat -> Type
Arr n = Vec n Int

-- The element at `i`; 0 past the end.
readAt : {n : Nat} -> (1 _ : Arr n) -> Nat -> Res Int (const (Arr n))
readAt a i = case choose (i < n) of
  Left inside => Vec.read a (natToFinLt i @{inside})
  Right _ => 0 # a

-- The vector with `x` at `i`; as it was past the end.
writeAt : {n : Nat} -> (1 _ : Arr n) -> Nat -> Int -> Arr n
writeAt a i x = case choose (i < n) of
  Left inside => Vec.write a (natToFinLt i @{inside}) x
  Right _ => a

-- perm1[i] := i.
iota : {n : Nat} -> (1 _ : Arr n) -> Nat -> Arr n
iota a i = case choose (i < n) of
  Left inside => iota (Vec.write a (natToFinLt i @{inside}) (cast i)) (S i)
  Right _ => a

copy : {n : Nat} -> (1 _ : Arr n) -> (1 _ : Arr n) -> Nat -> LPair (Arr n) (Arr n)
copy from to i = case choose (i < n) of
  Left inside =>
    let at = natToFinLt i @{inside}
        v # from' = Vec.read from at
    in copy from' (Vec.write to at v) (S i)
  Right _ => from # to

-- Reverses perm[i..j].
rev : {n : Nat} -> (1 _ : Arr n) -> Nat -> Nat -> Arr n
rev p i j =
  if i >= j then p
  else let a # p1 = readAt p i
           b # p2 = readAt p1 j
       in rev (writeAt (writeAt p2 i b) j a) (S i) (pred j)

-- The number of prefix reversals (each of perm[0..perm[0]]) that brings 0
-- to the front.
flips : {n : Nat} -> (1 _ : Arr n) -> Int -> Res Int (const (Arr n))
flips p k =
  let h # p1 = readAt p 0 in
  if h == 0 then k # p1 else flips (rev p1 0 (cast h)) (k + 1)

shift : {n : Nat} -> (1 _ : Arr n) -> Nat -> Nat -> Arr n
shift p r i =
  if i >= r then p
  else let v # p1 = readAt p (S i) in shift (writeAt p1 i v) r (S i)

-- Rotates perm1[0..r] left by one.
rotate : {n : Nat} -> (1 _ : Arr n) -> Nat -> Arr n
rotate p r = let p0 # p1 = readAt p 0 in writeAt (shift p1 r 0) r p0

-- The next permutation's r with the vectors, or the vectors when they are
-- exhausted.
data Next : Nat -> Type where
  Done : (1 _ : Arr n) -> (1 _ : Arr n) -> Next n
  More : Nat -> (1 _ : Arr n) -> (1 _ : Arr n) -> Next n

next : {n : Nat} -> (1 _ : Arr n) -> (1 _ : Arr n) -> Nat -> Next n
next perm1 count r =
  if r == n then Done perm1 count
  else let perm1' = rotate perm1 r
           c # count1 = readAt count r
           count' = writeAt count1 r (c - 1)
       in if c > 1 then More r perm1' count' else next perm1' count' (S r)

-- count[i] := i + 1 for i below r.
counters : {n : Nat} -> (1 _ : Arr n) -> Nat -> Arr n
counters count r = if r <= 1 then count else counters (writeAt count (pred r) (cast r)) (pred r)

discard : (1 _ : Arr n) -> ()
discard a = let MkBang _ = Vec.freeze a in ()

loop : {n : Nat} -> (1 _ : Arr n) -> (1 _ : Arr n) -> (1 _ : Arr n) -> Nat -> Int -> Int -> Int -> !* (Int, Int)
loop perm1 perm count r idx checksum maxf =
  let count1 = counters count r
      perm1' # perm' = copy perm1 perm 0
      f # perm'' = flips perm' 0
      checksum' = if idx `mod` 2 == 0 then checksum + f else checksum - f
      maxf' = max maxf f
  in case next perm1' count1 1 of
       Done a b => let () = discard a in let () = discard b in let () = discard perm'' in MkBang (checksum', maxf')
       More r' a b => loop a perm'' b r' (idx + 1) checksum' maxf'

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
          loop (iota perm1 0) perm count n 0 0 0)))

main : IO ()
main = do
  n <- readInt
  let (checksum, maxf) = run (cast n)
  printLn checksum
  putStrLn ("Pfannkuchen(" ++ show n ++ ") = " ++ show maxf)
