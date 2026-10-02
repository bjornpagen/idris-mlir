module Main

-- spectral-norm (the Benchmarks Game) in pure code over Linear.Array's
-- loops over an array's index space: the largest eigenvalue of an
-- infinite matrix, by ten rounds of the power method. Each product with A
-- (or its transpose) is one array generated from its rows, each row's
-- value the dot product with v as an ordered fold over v, summed in index
-- order as the C version sums it; A(i, j) is computed, never stored. The
-- vectors are frozen between the products, so that every row reads them,
-- and the compiler runs each product as one two-dimensional loop nest it
-- tiles and vectorizes along the rows.

import Prelude
import Data.List
import Linear.Notation
import Linear.Array

a : Int -> Int -> Double
a i j = 1.0 / cast (((i + j) * (i + j + 1)) `div` 2 + i + 1)

-- A(i, j), or A(j, i) for the transpose.
aAt : Bool -> Int -> Int -> Double
aAt transposed i j = if transposed then a j i else a i j

-- Row i of A (or of its transpose) times v, for every i: the sum over j,
-- in index order.
mulAv : Bool -> Int -> IArray Double -> Array Double
mulAv transposed n v = generate n (\i => ifoldl (\acc, j, x => acc + aAt transposed i j * x) 0.0 v)

-- Aᵀ (A v).
mulAtAv : Int -> IArray Double -> Array Double
mulAtAv n v = freeze (mulAv False n v) (mulAv True n)

-- k rounds of the power method: v := Aᵀ A u, u := Aᵀ A v.
iter : Int -> Int -> IArray Double -> IArray Double -> (IArray Double, IArray Double)
iter n k u v =
  if k <= 0 then (u, v)
  else freeze (mulAtAv n u) (\v' => freeze (mulAtAv n v') (\u' => iter n (k - 1) u' v'))

-- The dot products u·v and v·v, in index order.
run : Int -> Double
run n =
  freeze (mkArray n 1.0) (\u0 => freeze (mkArray n 0.0) (\v0 =>
    let (u, v) = iter n 10 u0 v0
        uv = freeze (zipWith (*) u v) sum
        vv = freeze (zipWith (*) v v) sum
    in sqrt (uv / vv)))

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
