module Main

-- Closed calls of partial functions that may never end: `spin 0` loops
-- forever, and runs only on the input 9, which this test does not give;
-- `safeDiv 84 2` reaches spin only on a divisor of 0, a path the call does
-- not take; `collatz` is not known to terminate for every start. A closed
-- call runs at run time, so every call stays, and the program prints what
-- the ones it takes return.

import Prelude

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
  c <- getChar
  if c == '9'
    then printLn (spin 0)
    else putStrLn "not taken"
  printLn (safeDiv 84 2)
  printLn (collatz 97 0)
  printLn (collatz 27 0)
