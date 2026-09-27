module Main

-- Partial sums of the harmonic and alternating series: a tight
-- floating-point loop of divisions.

import Prelude

series : Int -> Int -> Double -> Double -> (Double, Double)
series i n h a =
  if i > n then (h, a)
  else let x = 1.0 / cast i in
       series (i + 1) n (h + x) (if i `mod` 2 == 0 then a - x else a + x)

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
  let (h, a) = series 1 n 0.0 0.0
  printLn h
  printLn a
