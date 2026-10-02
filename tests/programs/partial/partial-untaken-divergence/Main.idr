module Main

-- Closed calls of partial functions, each of which diverges on a path the
-- call does not take: `safeDiv x 0` spins forever, and `collatz` is not
-- known to terminate for every start. Both calls end, so they are evaluated
-- at compile time, as Idris's own evaluator would reduce them, and the
-- program prints constants.

import Prelude

-- An infinite loop.
partial
spin : Int -> Int
spin x = spin (x + 1)

partial
safeDiv : Int -> Int -> Int
safeDiv x 0 = spin x
safeDiv x y = x `div` y

partial
collatz : Int -> Int -> Int
collatz 1 steps = steps
collatz n steps = collatz (if n `mod` 2 == 0 then n `div` 2 else 3 * n + 1) (steps + 1)

partial
main : IO ()
main = do
  printLn (safeDiv 84 2)
  printLn (collatz 27 0)
