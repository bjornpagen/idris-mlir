module Main

-- A closed call stays in the program: nothing evaluates it at compile
-- time, so it runs at run time, recursion included, whether or not Idris
-- proves the function terminating. `fib n` and `euclid (n * 462) 1071`
-- take their arguments from the input. The other calls are closed and run
-- the same way.

import Prelude

fib : Int -> Int
fib n = if n < 2 then n else fib (n - 1) + fib (n - 2)

euclid : Integral a => Eq a => a -> a -> a
euclid a b = if b == 0 then a else euclid b (a `mod` b)

power : Num a => a -> Nat -> a
power x Z = 1
power x (S k) = x * power x k

main : IO ()
main = do
  c <- getChar
  let n = the Int (cast (ord c) - 48)
  printLn (fib 15)
  printLn (fib 27)
  printLn (fib n)
  printLn (euclid (n * 462) 1071)
  printLn (euclid (the Integer 1071) 462)
  printLn (power (the Integer 2) 100)
  printLn (cast {to = Int} (power (the Integer 3) 20 `mod` 1000))
  printLn (power (the Double 1.5) 10)
