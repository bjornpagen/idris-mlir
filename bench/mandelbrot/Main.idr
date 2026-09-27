module Main

-- Counts the points of an n x n grid over [-1.5, 0.5] x [-1, 1] that stay
-- bounded for 50 iterations of z^2 + c.

import Arith

%default partial

escapes : Double -> Double -> Bool
escapes cr ci = go 0.0 0.0 0
  where
    go : Double -> Double -> Int -> Bool
    go zr zi i =
      if i >= 50 then False
      else let zr2 = zr * zr
               zi2 = zi * zi
           in if zr2 + zi2 > 4.0 then True
              else go (zr2 - zi2 + cr) (2.0 * zr * zi + ci) (i + 1)

row : Int -> Double -> Int -> Int -> Int
row n ci x acc =
  if x >= n then acc
  else let cr = 2.0 * toDouble x / toDouble n - 1.5
       in row n ci (x + 1) (if escapes cr ci then acc else acc + 1)

grid : Int -> Int -> Int -> Int
grid n y acc =
  if y >= n then acc
  else grid n (y + 1) (row n (2.0 * toDouble y / toDouble n - 1.0) 0 acc)

main : IO ()
main = do
  n <- readInt
  printInt (grid n 0 0)
