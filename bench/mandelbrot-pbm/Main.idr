module Main

-- mandelbrot (the Benchmarks Game): a portable bitmap of the set, eight
-- pixels to a byte, fifty iterations, written byte by byte.

import Prelude

inSet : Double -> Double -> Bool
inSet cr ci = go 0.0 0.0 0
  where
    go : Double -> Double -> Int -> Bool
    go zr zi i =
      if i >= 50 then True
      else let zr2 = zr * zr
               zi2 = zi * zi
           in if zr2 + zi2 > 4.0 then False
              else go (zr2 - zi2 + cr) (2.0 * zr * zi + ci) (i + 1)

-- The byte for pixels x .. x + 7 of row ci; pixels past n are clear.
byte : Int -> Double -> Int -> Int -> Int -> Int
byte n ci x k acc =
  if k == 8 then acc
  else let px = x + k
           bit = if px < n && inSet (2.0 * cast px / cast n - 1.5) ci then 1 else 0
       in byte n ci x (k + 1) (acc * 2 + bit)

row : Int -> Double -> Int -> IO ()
row n ci x =
  if x >= n then pure ()
  else do
    putChar (chr (byte n ci x 0 0))
    row n ci (x + 8)

rows : Int -> Int -> IO ()
rows n y =
  if y >= n then pure ()
  else do
    row n (2.0 * cast y / cast n - 1.0) 0
    rows n (y + 1)

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
  putStrLn ("P4\n" ++ show n ++ " " ++ show n)
  rows n 0
