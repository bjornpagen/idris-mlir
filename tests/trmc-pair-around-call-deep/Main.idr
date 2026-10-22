module Main

import Prelude

-- A self call inside a pair inside a cell, a million levels deep: the
-- pair and the cell are built for the call alone, so both are built first
-- and the call fills the pair's second part in a loop that grows no stack.

data Nest = Stop | Step (Int, Nest)

nest : Int -> Nest
nest 0 = Stop
nest n = Step (n, nest (n - 1))

walk : Int -> Int -> Nest -> (Int, Int)
walk c s Stop = (c, s)
walk c s (Step (x, rest)) = walk (c + 1) (s + x) rest

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
  printLn (walk 0 0 (nest n))
