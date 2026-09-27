module Main

-- Doubly recursive Fibonacci: calls and returns, no loops.

import Prelude


fib : Int -> Int
fib n = if n < 2 then n else fib (n - 1) + fib (n - 2)

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
  printLn (fib n)
