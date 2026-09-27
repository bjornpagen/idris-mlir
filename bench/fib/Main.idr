module Main

-- Doubly recursive Fibonacci: calls and returns, no loops.

import Arith

%default partial

fib : Int -> Int
fib n = if n < 2 then n else fib (n - 1) + fib (n - 2)

main : IO ()
main = do
  n <- readInt
  printInt (fib n)
