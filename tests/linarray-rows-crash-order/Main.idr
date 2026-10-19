module Main

-- A vector tabulated over rows whose every element is a fold over another
-- vector, with a fold step that divides by values that reach zero at two
-- places: the `mod` at row 1, column 1, the `div` at row 2, column 0. In
-- the program's order row 1 comes first, so the program ends at the
-- `mod`. The step may crash, so the loop is no structured operation the
-- compiler may reorder: it runs as the program does, row by row; tiled
-- four rows at a time, it would run column 0 of rows 0 to 3 first and end
-- at the `div`.

import Prelude
import Array

-- A position as the Int the program computes with.
at : Fin n -> Int
at i = cast (finToNat i)

rows : (n : Nat) -> {m : Nat} -> Vector m Int -> Vector n Int
rows n v =
  tabulate [<n] (\[<i] =>
    foldl (\acc, (j, x) => acc + ((x `div` (at i * 10 + j - 20)) + (x `mod` (at i * 10 + j - 11)))) 0
          (tabulate [<m] (\[<j] => (at j, v !! [<j]))))

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
  printLn (sum (rows (cast n) (tabulate [<cast m] (\[<k] => at k + 100))))
  putStrLn "after"
