module Main

-- spectral-norm (the Benchmarks Game) in pure code over linear arrays
-- (Linear.Array): the largest eigenvalue of an infinite matrix, by ten
-- rounds of the power method, each lane summed in index order as the C
-- version sums it. The vectors u, v and the temporary are arrays of
-- doubles threaded at quantity 1, so every element is written in place
-- without an IO monad, and A(i, j) is computed, never stored.

import Prelude
import Data.List
import Linear.Notation
import Linear.Array

Vec : Type
Vec = Array Double

a : Int -> Int -> Double
a i j = 1.0 / cast (((i + j) * (i + j + 1)) `div` 2 + i + 1)

-- A(i, j), or A(j, i) for the transpose.
aAt : Bool -> Int -> Int -> Double
aAt transposed i j = if transposed then a j i else a i j

-- The dot product of row i of A (or of its transpose) with v: the sum over
-- j, in index order.
dotRow : Bool -> Int -> Int -> (1 _ : Vec) -> Int -> Double -> Res Double (const Vec)
dotRow transposed n i v j acc =
  if j >= n then acc # v
  else case read v j of
         x # v' => dotRow transposed n i v' (j + 1) (acc + aAt transposed i j * x)

-- out[i] := row i of A (or of its transpose) times v, for every i.
mulAv : Bool -> Int -> (1 _ : Vec) -> (1 _ : Vec) -> Int -> LPair Vec Vec
mulAv transposed n v out i =
  if i >= n then v # out
  else let s # v' = dotRow transposed n i v 0 0.0
       in mulAv transposed n v' (write out i s) (i + 1)

-- out := Aᵀ (A v), through the temporary.
mulAtAv : Int -> (1 _ : Vec) -> (1 _ : Vec) -> (1 _ : Vec) -> LPair Vec (LPair Vec Vec)
mulAtAv n v out tmp =
  let v' # tmp' = mulAv False n v tmp 0
      tmp'' # out' = mulAv True n tmp' out 0
  in v' # (out' # tmp'')

iter : Int -> Int -> (1 _ : Vec) -> (1 _ : Vec) -> (1 _ : Vec) -> LPair Vec (LPair Vec Vec)
iter n k u v tmp =
  if k <= 0 then u # (v # tmp)
  else let u' # (v' # tmp') = mulAtAv n u v tmp
           v'' # (u'' # tmp'') = mulAtAv n v' u' tmp'
       in iter n (k - 1) u'' v'' tmp''

-- The dot products u·v and v·v, in index order.
dots : Int -> (1 _ : Vec) -> (1 _ : Vec) -> Int -> Double -> Double -> LPair (Double, Double) (LPair Vec Vec)
dots n u v i uv vv =
  if i >= n then (uv, vv) # (u # v)
  else let x # u' = read u i
           y # v' = read v i
       in dots n u' v' (i + 1) (uv + x * y) (vv + y * y)

discard : (1 _ : Vec) -> ()
discard arr = freeze arr (\_ => ())

run : Int -> Double
run n =
  let 1 u = mkArray n 1.0
      1 v = mkArray n 0.0
      1 tmp = mkArray n 0.0
      u' # (v' # tmp') = iter n 10 u v tmp
      () = discard tmp'
      (uv, vv) # (u'' # v'') = dots n u' v' 0 0.0 0.0
      () = discard u''
      () = discard v''
  in sqrt (uv / vv)

-- x with d decimals, for a non-negative x.
fixed : Nat -> Double -> String
fixed d x =
  let scale = cast {to = Int} (pow 10.0 (cast d))
      s = cast {to = Int} (x * cast scale + 0.5)
      frac = show (s `mod` scale)
  in show (s `div` scale) ++ "." ++ pack (replicate (minus d (length frac)) '0') ++ frac

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
  putStrLn (fixed 9 (run n))
