module Main

-- spectral-norm (the Benchmarks Game) in pure code over typed arrays
-- (Array): the largest eigenvalue of an infinite matrix, by ten rounds of
-- the power method. Each product with A (or its transpose) is one vector
-- tabulated over its rows, each row's value the sum of its products with
-- v, added in index order as the C version adds them; A(i, j) is computed,
-- never stored. The vectors are values, read by every row, and the
-- compiler structures each product as a loop nest it tiles and vectorizes
-- along the rows.

import Prelude
import Data.List
import Array

a : Int -> Int -> Double
a i j = 1.0 / cast (((i + j) * (i + j + 1)) `div` 2 + i + 1)

-- A(i, j), or A(j, i) for the transpose.
aAt : Bool -> Int -> Int -> Double
aAt transposed i j = if transposed then a j i else a i j

-- A position as the Int A is written over.
at : Fin n -> Int
at i = cast (finToNat i)

-- Row i of A (or of its transpose) times v, for every i: the sum over j,
-- in index order.
mulAv : Bool -> (n : Nat) -> Vector n Double -> Vector n Double
mulAv transposed n v =
  tabulate [<n] (\[<i] => sum (tabulate [<n] (\[<j] => aAt transposed (at i) (at j) * v !! [<j])))

-- Aᵀ (A v).
mulAtAv : (n : Nat) -> Vector n Double -> Vector n Double
mulAtAv n v = mulAv True n (mulAv False n v)

-- k rounds of the power method: v := Aᵀ A u, u := Aᵀ A v.
iter : (n : Nat) -> Nat -> Vector n Double -> Vector n Double -> (Vector n Double, Vector n Double)
iter n Z u v = (u, v)
iter n (S k) u v = let v' = mulAtAv n u in iter n k (mulAtAv n v') v'

-- The dot products u·v and v·v, in index order.
run : Nat -> Double
run n =
  let (u, v) = iter n 10 (fill [<n] 1.0) (fill [<n] 0.0)
      uv = sum (zipWith (*) u v)
      vv = sum (zipWith (*) v v)
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
  putStrLn (fixed 9 (run (cast n)))
