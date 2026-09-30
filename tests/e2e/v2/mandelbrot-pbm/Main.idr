module Main

import Prelude

-- The benchmarks game's mandelbrot: a PBM image, 8 pixels to a byte. Its
-- bytes from 128 on are characters written by putChar, so they come out in
-- UTF-8 and the image is not a PBM; the stock Chez backend writes each as
-- one byte (chez-differs). A correct image needs byte output, which the
-- supported subset does not have yet: Data.Buffer (setBits8) and
-- System.File.Buffer.writeBufferData on stdout are both rejected.
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

-- The byte of pixels x to x + 7 of a row: a set bit is a point that stays.
byte : Int -> Double -> Int -> Int -> Int -> Int
byte n ci x k acc =
  if k >= 8 then acc
  else let px = x + k
           cr = 2.0 * cast px / cast n - 1.5
           inside = px < n && not (escapes cr ci)
       in byte n ci x (k + 1) (acc * 2 + (if inside then 1 else 0))

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
  putStr ("P4\n" ++ show n ++ " " ++ show n ++ "\n")
  rows n 0
