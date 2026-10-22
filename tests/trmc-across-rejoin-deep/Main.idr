module Main

import Prelude

-- A filter a million elements long: the self call sits under a cell in
-- one branch and in tail position in the other, the two rejoining after
-- the test. Both are one loop that fills the pending cell's tail, so no
-- level grows the stack whichever branch it takes.

keepOdd : List Int -> List Int
keepOdd [] = []
keepOdd (x :: xs) = if x `mod` 2 == 1 then x :: keepOdd xs else keepOdd xs

upTo : Int -> List Int -> List Int
upTo n acc = if n <= 0 then acc else upTo (n - 1) (n :: acc)

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
  printLn (countSum 0 0 (keepOdd (upTo n [])))
