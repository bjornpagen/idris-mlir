-- Four LeetCode list problems on linear lists whose length is read at run
-- time, each answered by relinking the input's own cells: reverse a list
-- (206); remove the k-th node from the end (19), the length counted by a
-- pass that reverses the list into its own cells and back; rotate right by
-- k (61), a split and an append under the constructor; and a palindrome
-- check (234), one half reversed in place and compared with the other.
module Main

import Prelude
import Linear.Notation
import Linear.List

build : Int -> LList (!* Int) -@ LList (!* Int)
build n acc = if n <= 0 then acc else build (n - 1) (MkBang n :: acc)

rev : LList (!* Int) -@ LList (!* Int) -@ LList (!* Int)
rev [] acc = acc
rev (x :: xs) acc = rev xs (x :: acc)

-- A length with the list given back, reversed into its own cells on the
-- way and reversed again: two passes in place, each a loop.
data Counted : Type where
  MkCounted : Int -> (1 _ : LList (!* Int)) -> Counted

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

-- The first k cells, taken off into an accumulator and reversed back.
splitRev : Int -> LList (!* Int) -@ LList (!* Int) -@ LPair (LList (!* Int)) (LList (!* Int))
splitRev _ [] acc = acc # []
splitRev k (x :: xs) acc = if k <= 0 then acc # (x :: xs) else splitRev (k - 1) xs (x :: acc)

splitAt' : Int -> LList (!* Int) -@ LPair (LList (!* Int)) (LList (!* Int))
splitAt' k xs = let (a # b) = splitRev k xs [] in rev a [] # b

app : LList (!* Int) -@ LList (!* Int) -@ LList (!* Int)
app [] ys = ys
app (x :: xs) ys = x :: app xs ys

rotate : Int -> LList (!* Int) -@ LList (!* Int)
rotate k xs =
  let MkCounted n xs' = length' xs
      (a # b) = splitAt' (n - (k `mod` n)) xs'
  in app b a

-- 1 .. n .. 1, and the same with the middle spoiled.
mirror : Int -> Bool -> LList (!* Int)
mirror n spoil = go 1 (if spoil then build n (MkBang 0 :: []) else build n [])
  where
    go : Int -> LList (!* Int) -@ LList (!* Int)
    go k acc = if k > n then acc else go (k + 1) (MkBang k :: acc)

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
  putStrLn (render (rev (build 10 []) []) "")
  printLn (sumL (rev (rev (build n []) []) []) 0)
  putStrLn (render (removeKth 2 (build (n `div` 20000) [])) "")
  printLn (sumL (removeKth 12345 (build n [])) 0)
  putStrLn (render (rotate 3 (build (n `div` 10000) [])) "")
  printLn (sumL (rotate 12345 (build n [])) 0)
  printLn (palindrome (mirror (n `div` 12500) False))
  printLn (palindrome (mirror (n `div` 12500) True))
  printLn (palindrome (build (n `div` 12500) []))
  printLn (palindrome (mirror n False))
  printLn (palindrome (mirror n True))
