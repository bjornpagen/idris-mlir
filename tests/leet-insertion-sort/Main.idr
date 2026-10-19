-- Insertion sort list (LeetCode 147), on a linear list: each cell is
-- unlinked from the input and relinked into the sorted output. The sorted
-- list is in order and a permutation of the input (the same count, sum and
-- sum of squares, printed for each), and the order check fails on the
-- input itself.
module Main

import Prelude
import Linear.Notation
import Linear.List

build : Int -> Int -> LList (!* Int) -@ LList (!* Int)
build n seed acc =
  if n <= 0 then acc
  else let seed' = (seed * 1103515245 + 12345) `mod` 2147483648
       in build (n - 1) seed' (MkBang ((seed' `div` 65536) `mod` 1000) :: acc)

insert : Int -> LList (!* Int) -@ LList (!* Int)
insert x [] = MkBang x :: []
insert x (MkBang y :: ys) =
  if x <= y then MkBang x :: MkBang y :: ys else MkBang y :: insert x ys

isort : LList (!* Int) -@ LList (!* Int) -@ LList (!* Int)
isort [] acc = acc
isort (MkBang x :: xs) acc = isort xs (insert x acc)

render : (1 xs : LList (!* Int)) -> String -> String
render [] acc = acc
render (MkBang x :: xs) acc = render xs (acc ++ show x ++ " ")

drain : LList (!* Int) -@ ()
drain [] = ()
drain (MkBang _ :: xs) = drain xs

sorted : (1 xs : LList (!* Int)) -> Int -> Int -> Bool
sorted [] _ _ = True
sorted (MkBang x :: xs) prev count = if x < prev then let 1 () = drain xs in False else sorted xs x (count + 1)

-- The count, the sum and the sum of squares, which a permutation keeps.
stats : (1 xs : LList (!* Int)) -> (Int, Int, Int) -> (Int, Int, Int)
stats [] acc = acc
stats (MkBang x :: xs) (c, s, q) = stats xs (c + 1, s + x, q + x * x)

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
  putStrLn (render (isort (build (n `div` 250) 3 []) []) "")
  printLn (sorted (isort (build n 5 []) []) 0 0)
  printLn (stats (isort (build n 5 []) []) (0, 0, 0))
  printLn (stats (build n 5 []) (0, 0, 0))
  printLn (sorted (build n 5 []) 0 0)
