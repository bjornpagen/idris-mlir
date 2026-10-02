module Main

-- A closed call of a partial function that never ends: `spin 0`.
-- Compile-time evaluation runs it metered, stops it once it has spent its
-- budget, and leaves the call to run at runtime, as Idris's own backends
-- leave every call: the program compiles, and runs the call only on the
-- input 9, which this test does not give. The closed call after it is
-- evaluated as usual.

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
