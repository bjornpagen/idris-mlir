module Main

import Prelude

-- step is the one definition edited/Main.idr changes: only its body.
step : Int -> Int
step x = x * 5 + 2

twice : (Int -> Int) -> Int -> Int
twice f x = f (f x)

sumWith : (Int -> Int) -> List Int -> Int
sumWith f [] = 0
sumWith f (x :: xs) = f x + sumWith f xs

main : IO ()
main = do
  line <- getLine
  let n = cast {to = Int} line
  printLn (twice step n)
  printLn (sumWith (\x => x + n) [1, 2, 3])
  printLn (sumWith step [n, n + 1])
