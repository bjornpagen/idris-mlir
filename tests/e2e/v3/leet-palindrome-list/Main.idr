-- Palindrome linked list (LeetCode 234), on a linear list: the first half
-- is reversed in its own cells and compared with the second.
module Main

import Prelude
import Data.Linear.Notation
import Data.Linear.LList

build : Int -> LList (!* Int) -@ LList (!* Int)
build n acc = if n <= 0 then acc else build (n - 1) (MkBang n :: acc)

-- 1 .. n .. 1, and the same with the middle spoiled.
mirror : Int -> Bool -> LList (!* Int)
mirror n spoil = go 1 (if spoil then build n (MkBang 0 :: []) else build n [])
  where
    go : Int -> LList (!* Int) -@ LList (!* Int)
    go k acc = if k > n then acc else go (k + 1) (MkBang k :: acc)

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

-- The first k cells, taken off into an accumulator and reversed back.
splitRev : Int -> LList (!* Int) -@ LList (!* Int) -@ LPair (LList (!* Int)) (LList (!* Int))
splitRev _ [] acc = acc # []
splitRev k (x :: xs) acc = if k <= 0 then acc # (x :: xs) else splitRev (k - 1) xs (x :: acc)

splitAt' : Int -> LList (!* Int) -@ LPair (LList (!* Int)) (LList (!* Int))
splitAt' k xs = let (a # b) = splitRev k xs [] in rev a [] # b

drain : LList (!* Int) -@ ()
drain [] = ()
drain (MkBang _ :: xs) = drain xs

same : LList (!* Int) -@ LList (!* Int) -@ Bool
same [] ys = let 1 () = drain ys in True
same xs [] = let 1 () = drain xs in True
same (MkBang x :: xs) (MkBang y :: ys) =
  if x == y then same xs ys else let 1 () = drain xs in let 1 () = drain ys in False

drop' : Int -> LList (!* Int) -@ LList (!* Int)
drop' _ [] = []
drop' k (MkBang x :: xs) = if k <= 0 then MkBang x :: xs else drop' (k - 1) xs

palindrome : LList (!* Int) -@ Bool
palindrome xs =
  let MkCounted n xs' = length' xs
      (a # b) = splitAt' (n `div` 2) xs'
  in same (rev a []) (drop' (n `mod` 2) b)

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
  printLn (palindrome (mirror (n `div` 12500) False))
  printLn (palindrome (mirror (n `div` 12500) True))
  printLn (palindrome (build (n `div` 12500) []))
  printLn (palindrome (mirror n False))
  printLn (palindrome (mirror n True))
