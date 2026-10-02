-- Rotate a linked list right by k (LeetCode 61), on a linear list: split
-- at length - k, then append the second part in front; the append under
-- the constructor is a loop over reused cells.
module Main

import Prelude
import Linear.Notation
import Linear.List

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
  putStrLn (render (rotate 3 (build (n `div` 10000) [])) "")
  printLn (sumL (rotate 12345 (build n [])) 0)
