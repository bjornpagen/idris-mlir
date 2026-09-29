module Main

-- A closed call is evaluated at compile time, recursion included, whether
-- or not Idris proves the function terminating. `power` recurses on a Nat,
-- so `power (the Integer 2) 100` and `power (the Integer 3) 20` are
-- constants, and no Integer exists at runtime. `fib` and `euclid` recurse
-- on values Idris cannot see decrease, so they are partial, and their
-- closed calls are evaluated too: `fib 15`, `fib 27` and
-- `euclid (the Integer 1071) 462` are constants, and only `fib n` and
-- `euclid (n * 462) 1071`, whose arguments come from the input, run at
-- runtime.

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
