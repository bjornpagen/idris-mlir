module Main

-- A generate whose function is a fold over a frozen array, which this
-- compiler makes one loop over rows and columns, with a fold step that
-- divides by values that reach zero at two places: the `mod` at row 1,
-- column 1, the `div` at row 2, column 0. In the program's order row 1 comes
-- first, so the program ends at the `mod`. The step crashes, so it is no
-- body the vectorizer takes, and the loop runs as the program does, row by
-- row; tiled four rows at a time, it would run column 0 of rows 0 to 3
-- first and end at the `div`.

import Prelude
import Linear.Notation
import Linear.Array

rows : Int -> IArray Int -> Array Int
rows n v = generate n (\i => ifoldl (\acc, j, x => acc + ((x `div` (i * 10 + j - 20)) + (x `mod` (i * 10 + j - 11)))) 0 v)

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
  m <- readInt
  putStrLn "before"
  printLn (freeze (generate m (\k => k + 100)) (\v => freeze (rows n v) Linear.Array.sum))
  putStrLn "after"
