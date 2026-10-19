module Main

import Prelude

-- swap passes its two type arguments, and their Show implementations,
-- swapped at each call: its recursive group calls itself at an instance
-- other than its own, but the instances it reaches are two, a finite set
-- the chain of requests from main closes, so it compiles to the code two
-- monomorphic functions would be, at a known depth and at one read from
-- the input. An even depth shows the arguments in their order, an odd one
-- swapped.

swap : Show a => Show b => Nat -> a -> b -> String
swap Z x y = show x ++ " " ++ show y
swap (S k) x y = swap k y x

main : IO ()
main = do
  putStrLn (swap 3 (the Int 1) "two")
  putStrLn (swap 4 (the Int 1) "two")
  putStrLn (swap 0 (the Int 1) "two")
  c <- getChar
  putStrLn (swap (cast (ord c - 48)) (the Int 1) "two")
