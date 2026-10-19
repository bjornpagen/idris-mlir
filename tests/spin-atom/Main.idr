module Main

-- A loop that decides on a box goes round on one constructor and reads its
-- fields, and what it does not change runs once, before it. spin ends at
-- once on Small, the atom: a static cell that is its header alone. On a
-- Big it would go round for ever adding Big's third field, which does not
-- change: read before the loop, that read would load past the end of the
-- atom's cell whenever spin is given Small, as it is here. The read stays
-- in the loop, after the test of the tag.

import Prelude

data T = Small | Big Int Int Int T

readInt : IO Int
readInt = go 0
  where
    go : Int -> IO Int
    go acc = do
      c <- getChar
      if isDigit c then go (acc * 10 + cast (ord c - 48)) else pure acc

-- A T of n cells, so that spin is given no constant.
mk : Int -> T
mk 0 = Small
mk k = Big k 2 3 (mk (k - 1))

covering
spin : T -> Int -> Int
spin Small acc = acc
spin t@(Big _ _ c _) acc = spin t (acc + c)

main : IO ()
main = do
  n <- readInt
  printLn (spin (mk n) (n + 7))
