module Main

-- A closed call of a partial function that never ends: `spin 0`.
-- idr-eval is not in the simplify round, so the call stays and runs at
-- run time, and only on the input 9, which this test does not give. The
-- closed call of collatz stays and runs too.

import Prelude

partial
spin : Int -> Int
spin x = spin (x + 1)

partial
collatz : Int -> Int -> Int
collatz 1 steps = steps
collatz n steps = collatz (if n `mod` 2 == 0 then n `div` 2 else 3 * n + 1) (steps + 1)

partial
main : IO ()
main = do
  c <- getChar
  if c == '9'
    then printLn (spin 0)
    else putStrLn "not taken"
  printLn (collatz 97 0)
