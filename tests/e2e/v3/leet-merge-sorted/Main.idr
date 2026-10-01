-- Merge two sorted linked lists (LeetCode 21), on linear lists: the result
-- is relinked from the inputs' cells, and the recursion under the
-- constructor runs as a loop writing each cell's tail.
module Main

import Prelude
import Data.Linear.Notation
import Data.Linear.LList

-- n, n - step, ..., down to 1 or 2, prepended: ascending.
build : Int -> Int -> LList (!* Int) -@ LList (!* Int)
build n step acc = if n <= 0 then acc else build (n - step) step (MkBang n :: acc)

merge : LList (!* Int) -@ LList (!* Int) -@ LList (!* Int)
merge [] ys = ys
merge xs [] = xs
merge (MkBang x :: xs) (MkBang y :: ys) =
  if x <= y then MkBang x :: merge xs (MkBang y :: ys)
  else MkBang y :: merge (MkBang x :: xs) ys

drain : LList (!* Int) -@ ()
drain [] = ()
drain (MkBang _ :: xs) = drain xs

sorted : (1 xs : LList (!* Int)) -> Int -> Int -> Bool
sorted [] _ _ = True
sorted (MkBang x :: xs) prev count = if x < prev then let 1 () = drain xs in False else sorted xs x (count + 1)

render : (1 xs : LList (!* Int)) -> String -> String
render [] acc = acc
render (MkBang x :: xs) acc = render xs (acc ++ show x ++ " ")

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
  putStrLn (render (merge (build (n `div` 10000 - 1) 2 []) (build (n `div` 10000) 2 [])) "")
  printLn (sorted (merge (build (n - 1) 2 []) (build n 2 [])) 0 0)
