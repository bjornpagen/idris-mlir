module Main

-- A linear array's element-by-element functions, each in place and in
-- row-major order, the last axis fastest: map replaces each element by f
-- of it; foldl folds the elements from the left and gives the array back;
-- traverse replaces each element by what f gives for its index, the
-- element and a state threaded from each index to the next, and gives the
-- last state. Here the state writes down each position it visits, as a
-- digit, so it shows the order.

import Prelude
import Linear.Notation
import Array

-- A position as the Int the program computes with.
at : Fin n -> Int
at i = cast (finToNat i)

-- The element plus 10 times its row plus its column; the state with the
-- position's number, 3 times the row plus the column, written after it.
-- The state is linear, so the number travels in it unrestricted.
step : Index [<2, 3] -> Int -> (1 _ : !* Int) -> Res Int (const (!* Int))
step [<r, c] x (MkBang st) = (x + 10 * at r + at c) # MkBang (st * 10 + 3 * at r + at c)

-- From an array of 2 rows of 3, every element k: each doubled, their sum,
-- then each stepped, the last state and the elements.
run : Int -> (Int, Int, List Int)
run k = unrestricted $ withArray [<2, 3] k (\a0 =>
  let a1 = LArray.map (* 2) a0
      added # a2 = LArray.foldl (+) 0 a1
      MkBang st # a3 = LArray.traverse step (MkBang 0) a2
      MkBang arr = LArray.freeze a3
  in MkBang (added, st, toList arr))

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
  printLn (run k)
