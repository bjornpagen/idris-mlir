module Main

import Prelude

-- A self call two constructors deep, a million levels: each level builds
-- both cells first and passes the second's tail as the place the next
-- level fills, so the recursion is a loop that grows no stack.

pairsUp : Int -> List Int
pairsUp 0 = []
pairsUp n = n :: (n * 2) :: pairsUp (n - 1)

countSum : Int -> Int -> List Int -> (Int, Int)
countSum c s [] = (c, s)
countSum c s (x :: xs) = countSum (c + 1) (s + x) xs

readInt : IO Int
readInt = go 0
  where
    go : Int -> IO Int
    go acc = do
      c <- getChar
      if isDigit c then go (acc * 10 + cast (ord c - 48)) else pure acc

main : IO ()
main = do
  n <- readInt
  printLn (countSum 0 0 (pairsUp n))
