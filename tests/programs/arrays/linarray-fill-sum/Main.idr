module Main

-- A linear array filled, then summed: pure code over Linear.Array, the
-- array threaded through every write and read at quantity 1, which this
-- compiler runs as one array cell and loops of stores and loads.

import Prelude
import Linear.Notation
import Linear.Array

fill : (1 _ : Array Int) -> Int -> Int -> Array Int
fill a n i = if i >= n then a else fill (write a i (i * 3)) n (i + 1)

sumTo : (1 _ : Array Int) -> Int -> Int -> Int -> Res Int (const (Array Int))
sumTo a n i acc =
  if i >= n then acc # a
  else let v # a' = read a i in sumTo a' n (i + 1) (acc + v)

readInt : IO Int
readInt = go 0
  where
    go : Int -> IO Int
    go acc = do
      c <- getChar
      if isDigit c then go (acc * 10 + cast (ord c - 48)) else pure acc

-- The sum of the filled array, plus its first element and its size read
-- after it is frozen.
compute : Int -> Int
compute n = newArray n 0 $ \a =>
  let s # a' = sumTo (fill a n 0) n 0 0
  in freeze a' (\frozen => MkBang (s + iread frozen 0 + isize frozen))

main : IO ()
main = do
  n <- readInt
  printLn (compute n)
