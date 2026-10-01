-- Remove the k-th node from the end (LeetCode 19), on a linear list: the
-- length is counted by a pass that rebuilds the list in its own cells,
-- then the node is unlinked.
module Main

import Prelude
import Data.Linear.Notation
import Data.Linear.LList

build : Int -> LList (!* Int) -@ LList (!* Int)
build n acc = if n <= 0 then acc else build (n - 1) (MkBang n :: acc)

-- A length with the list given back, reversed into its own cells on the
-- way and reversed again: two passes in place, each a loop.
data Counted : Type where
  MkCounted : Int -> (1 _ : LList (!* Int)) -> Counted

rev : LList (!* Int) -@ LList (!* Int) -@ LList (!* Int)
rev [] acc = acc
rev (x :: xs) acc = rev xs (x :: acc)

countRev : (1 xs : LList (!* Int)) -> Int -> (1 acc : LList (!* Int)) -> Counted
countRev [] n acc = MkCounted n acc
countRev (x :: xs) n acc = countRev xs (n + 1) (x :: acc)

length' : LList (!* Int) -@ Counted
length' xs = let MkCounted n r = countRev xs 0 [] in MkCounted n (rev r [])

removeAt : Int -> LList (!* Int) -@ LList (!* Int)
removeAt _ [] = []
removeAt 0 (MkBang _ :: xs) = xs
removeAt i (x :: xs) = x :: removeAt (i - 1) xs

removeKth : Int -> LList (!* Int) -@ LList (!* Int)
removeKth k xs = let MkCounted n xs' = length' xs in removeAt (n - k) xs'

render : (1 xs : LList (!* Int)) -> String -> String
render [] acc = acc
render (MkBang x :: xs) acc = render xs (acc ++ show x ++ " ")

sumL : (1 xs : LList (!* Int)) -> Int -> Int
sumL [] acc = acc
sumL (MkBang x :: xs) acc = sumL xs (acc * 7 + x)

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
  putStrLn (render (removeKth 2 (build (n `div` 20000) [])) "")
  printLn (sumL (removeKth 12345 (build n [])) 0)
