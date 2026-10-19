module Main

-- Memoization, observed without an effect. Each stream below is read by
-- two consumers, and each of its cells is computed from cells before it,
-- each read twice. A cell that keeps its value once forced makes the 90th
-- Fibonacci number ninety additions; one that computed it again at every
-- read would make it about as many additions as the number itself, far
-- past the time the test allows.

import Prelude

addS : Stream Int -> Stream Int -> Stream Int
addS (x :: xs) (y :: ys) = (x + y) :: addS xs ys

-- A top-level stream, whose tail reads the stream itself twice over.
fibs : Stream Int
fibs = 0 :: 1 :: addS fibs (tail fibs)

-- A stream made at run time from a seed: each element is a suspension of
-- the sum of the two before it, which the next suspension reads again.
fibsFrom : Lazy Int -> Lazy Int -> Stream Int
fibsFrom a b = a :: fibsFrom b (a + b)

at : Nat -> Stream Int -> Int
at Z (x :: _) = x
at (S k) (_ :: xs) = at k xs

main : IO ()
main = do
  printLn (at 90 fibs)
  printLn (at 91 fibs)
  c <- getChar
  let seed : Int = cast (ord c - ord '0')
  let seeded = fibsFrom seed seed
  printLn (at 85 seeded)
  printLn (at 88 seeded)
