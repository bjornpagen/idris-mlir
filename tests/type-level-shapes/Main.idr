module Main

-- Types that reduce on a runtime argument: each call's instance takes as
-- much of the argument's shape, the constructors it is written with, as
-- the type needs to reduce. Res looks at the outermost constructor, Res2
-- at two; count builds its argument deeper at each call, below what Res
-- looks at, so all those calls share one instance. Ints needs all of its
-- argument, and second's default clause calls second one constructor
-- deeper; at `S (S Z)` the shape rules that clause out, so its call is
-- never made.

import Prelude

Res : Nat -> Type
Res Z = String
Res (S _) = Integer

describe : (n : Nat) -> Res n -> String
describe Z s = "zero " ++ s
describe (S k) m = "succ " ++ show k ++ " " ++ show m

Res2 : Nat -> Type
Res2 (S (S _)) = Integer
Res2 _ = String

two : (n : Nat) -> Res2 n -> String
two (S (S k)) m = "two " ++ show k ++ " " ++ show m
two (S Z) s = "one " ++ s
two Z s = "zero " ++ s

count : (n : Nat) -> Res n -> Int -> Integer
count Z s _ = cast (length s)
count (S m) r 0 = r + cast m
count (S m) r k = count (S (S m)) (r + 1) (k - 1)

Ints : Nat -> Type
Ints Z = Int
Ints (S k) = (Int, Ints k)

second : (n : Nat) -> Ints n -> Int
second (S (S _)) (_, (b, _)) = b
second n x = second (S n) (0, x)

main : IO ()
main = do
  line <- getLine
  let k = the Nat (cast line)
  putStrLn (describe (S k) 5)
  putStrLn (describe Z "z")
  putStrLn (two (S (S k)) 3)
  putStrLn (two (S Z) "o")
  putStrLn (two Z "z")
  printLn (count (S k) 10 (cast k))
  printLn (count Z "four" 3)
  printLn (second (S (S Z)) (1, (cast k, 3)))
