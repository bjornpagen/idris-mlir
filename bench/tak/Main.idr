module Main

-- Takeuchi's function, a classic of the Gabriel benchmarks, iterated.

import Prelude
import IdrisMLIR.IO


tak : Int -> Int -> Int -> Int
tak x y z = if y < x then tak (tak (x - 1) y z) (tak (y - 1) z x) (tak (z - 1) x y) else z

repeat : Int -> Int -> Int -> Int
repeat 0 n acc = acc
repeat k n acc = repeat (k - 1) n (acc + tak (n + k `mod` 2) ((2 * n) `div` 3) (n `div` 3))

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
  printLn (repeat 1000 n 0)
