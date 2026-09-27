module Main

-- Takeuchi's function, a classic of the Gabriel benchmarks, iterated.

import Arith

%default partial

tak : Int -> Int -> Int -> Int
tak x y z = if y < x then tak (tak (x - 1) y z) (tak (y - 1) z x) (tak (z - 1) x y) else z

repeat : Int -> Int -> Int -> Int
repeat 0 n acc = acc
repeat k n acc = repeat (k - 1) n (acc + tak (n + mod k 2) (div (2 * n) 3) (div n 3))

main : IO ()
main = do
  n <- readInt
  printInt (repeat 1000 n 0)
