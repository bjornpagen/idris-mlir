module Main

-- rule: ELIM-G-16, SEM-BIG-1, ELIM-G-12
-- A call whose arguments are all known is evaluated at compile time,
-- recursion included, within a budget: `fib 15` is the constant 610, and
-- Euclid's algorithm runs on Integer, which has no runtime representation,
-- through the Prelude's Integral interface. `fib 27` exceeds the budget and
-- `fib n` depends on input; both are calls at runtime.

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
  printLn (euclid (the Integer 1071) 462)
  printLn (euclid (n * 462) 1071)
  printLn (power (the Integer 2) 100)
  printLn (cast {to = Int} (power (the Integer 3) 20 `mod` 1000))
  printLn (power (the Double 1.5) 10)
