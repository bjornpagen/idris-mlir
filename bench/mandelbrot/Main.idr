module Main

import Prelude
import IdrisMLIR.IO

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
  else let cr = 2.0 * cast x / cast n - 1.5
       in row n ci (x + 1) (if escapes cr ci then acc else acc + 1)

grid : Int -> Int -> Int -> Int
grid n y acc =
  if y >= n then acc
  else grid n (y + 1) (row n (2.0 * cast y / cast n - 1.0) 0 acc)

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
  printLn (grid n 0 0)
