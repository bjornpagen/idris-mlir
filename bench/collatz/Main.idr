module Main

-- The longest Collatz sequence starting below n: integer division in loops.

import Arith

%default partial

steps : Int -> Int -> Int
steps 1 acc = acc
steps m acc = steps (if mod m 2 == 0 then div m 2 else 3 * m + 1) (acc + 1)

longest : Int -> Int -> Int -> Int -> Int
longest n i best at =
  if i >= n then at
  else let s = steps i 0 in
       if s > best then longest n (i + 1) s i else longest n (i + 1) best at

main : IO ()
main = do
  n <- readInt
  printInt (longest n 1 0 1)
