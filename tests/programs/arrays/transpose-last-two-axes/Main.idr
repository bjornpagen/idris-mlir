module Main

-- A transpose swaps the last two axes: at p :< j :< i it holds the element
-- of the array at p :< i :< j. So a matrix of 2 rows of 3 becomes one of 3
-- rows of 2, an array of 2 such matrices becomes the array of their
-- transposes, and a transpose transposed is the array again. The elements
-- print in row-major order.

import Prelude
import Array

-- A position as the Int the program computes with.
at : Fin n -> Int
at i = cast (finToNat i)

-- grid k at [<i, j] is k + 10 i + j.
grid : Int -> Matrix 2 3 Int
grid k = tabulate [<2, 3] (\[<i, j] => k + 10 * at i + at j)

-- stack k at [<p, i, j] is k + 100 p + 10 i + j.
stack : Int -> Array [<2, 2, 3] Int
stack k = tabulate [<2, 2, 3] (\[<p, i, j] => k + 100 * at p + 10 * at i + at j)

readInt : IO Int
readInt = go 0
  where
    go : Int -> IO Int
    go acc = do
      c <- getChar
      if isDigit c then go (acc * 10 + cast (ord c - 48)) else pure acc

main : IO ()
main = do
  k <- readInt
  printLn (toList (grid k))
  printLn (toList (transpose (grid k)))
  printLn (toList (transpose (stack k)))
  printLn (toList (transpose (transpose (stack k))) == toList (stack k))
