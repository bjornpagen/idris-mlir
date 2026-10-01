module Main

-- spectral-norm (the Benchmarks Game): the largest eigenvalue of an
-- infinite matrix, by ten rounds of the power method over lists of
-- doubles, each lane summed in index order as the C version sums it.

import Prelude
import Data.List

a : Int -> Int -> Double
a i j = 1.0 / cast (((i + j) * (i + j + 1)) `div` 2 + i + 1)

dotRow : (Int -> Int -> Double) -> Int -> Int -> List Double -> Double -> Double
dotRow f i j [] acc = acc
dotRow f i j (u :: us) acc = dotRow f i (j + 1) us (acc + f i j * u)

mulAv : Int -> (Int -> Int -> Double) -> List Double -> List Double
mulAv n f u = map (\i => dotRow f i 0 u 0.0) [0 .. n - 1]

mulAtAv : Int -> List Double -> List Double
mulAtAv n u = mulAv n (\i, j => a j i) (mulAv n a u)

iter : Int -> Int -> List Double -> List Double -> (List Double, List Double)
iter n 0 u v = (u, v)
iter n k u v = let v' = mulAtAv n u
                   u' = mulAtAv n v'
               in iter n (k - 1) u' v'

dot : List Double -> List Double -> Double
dot xs ys = foldl (+) 0.0 (zipWith (*) xs ys)

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
  let (u, v) = iter n 10 (replicate (cast n) 1.0) []
  putStrLn (fixed 9 (sqrt (dot u v / dot v v)))
