module Main

-- An accumulating loop on naturals, a million steps read at runtime: each
-- step is a comparison with zero, a predecessor and Nat's plus, each of
-- them one runtime operation on a big, so the loop is linear in its count.
-- Nat's plus as written in the Prelude recurses on its first argument,
-- which made every step as long as the accumulator.

import Prelude

count : Nat -> Nat -> Nat
count Z acc = acc
count (S k) acc = count k (acc + 2)

main : IO ()
main = do
  c <- getChar
  let n = the Nat (cast (the Int (cast (ord c) - 48)) * 1000000)
  printLn (count n 0)
