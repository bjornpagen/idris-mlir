module Main

-- rule: PROF-PROG-4, PROF-LIB-1, ELIM-G-19, ELIM-G-20, SEM-BIG-1, SEM-REC-1
-- The stock Prelude, imported explicitly: Num, Neg, Integral, Eq, Ord,
-- Bool, if, && and ||, Maybe, Pair, cast, and show on Int, Double and Bool.
-- Its Integer literals, its Nat inside Prec and its show internals are all
-- evaluated at compile time; the program's own work runs at runtime.

import Prelude
import IdrisMLIR.IO

square : Int -> Int
square x = x * x

classify : Int -> String
classify n = if n > 10 then "big" else if n < 0 then "negative" else "small"

safeDiv : Int -> Int -> Maybe Int
safeDiv _ 0 = Nothing
safeDiv a b = Just (a `div` b)

describe : Maybe Int -> String
describe Nothing = "nothing"
describe (Just k) = "just"

collatz : Int -> Int -> Int
collatz 1 acc = acc
collatz n acc = collatz (if n `mod` 2 == 0 then n `div` 2 else 3 * n + 1) (acc + 1)

main : IO ()
main = do
  c <- getChar
  let n = the Int (cast (ord c) - 48)
  putStrLn (show (square n))
  putStrLn (classify n)
  putStrLn (classify (negate n))
  putStrLn (describe (safeDiv 100 n))
  putStrLn (describe (safeDiv 100 (n - 7)))
  putStrLn (show (collatz (n * 1000 + 1) 0))
  putStrLn (show (the Double (cast n) / 3.0 + 0.5))
  putStrLn (show (n > 3 && n < 9 || n == 42))
  putStrLn (show (fst (n, 2) + snd (3, n)))
  -- ELIM-G-20: a string built in one alternative of a runtime match.
  putStrLn (maybe "none" show (safeDiv 100 n))
  putStrLn (maybe "none" show (safeDiv 100 (n - 7)))
  putStrLn (show (n, n + 1))
