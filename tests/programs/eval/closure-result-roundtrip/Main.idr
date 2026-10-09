module Main

-- A value computed at compile time that holds functions: a list of partial
-- applications, made by mapping over a computed list. Evaluation gives the
-- whole list as one constant, closures and all; the program applies each
-- to a number it reads at run time.

import Prelude

scale : Int -> Int -> Int
scale k x = k * x + 1

odds : List Int
odds = filter (\k => k `mod` 2 == 1) [1 .. 9]

scalers : List (Int -> Int)
scalers = map scale odds

applyAll : List (Int -> Int) -> Int -> List Int
applyAll [] x = []
applyAll (f :: fs) x = f x :: applyAll fs x

main : IO ()
main = do
  c <- getChar
  printLn (applyAll scalers (cast (ord c - ord '0')))
