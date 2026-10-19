-- Remove duplicates from a sorted linked list (LeetCode 83), on a linear
-- list: a kept cell is rebuilt in place, a dropped one is freed. The result
-- is strictly increasing, which the check finds false of the input with its
-- runs, and holds each value once (its count).
module Main

import Prelude
import Linear.Notation
import Linear.List

-- Each k from n down to 1, k mod 3 + 1 times, prepended: ascending with runs.
build : Int -> Int -> LList (!* Int) -@ LList (!* Int)
build n k acc =
  if n <= 0 then acc
  else if k <= 0 then build (n - 1) ((n - 1) `mod` 3 + 1) acc
  else build n (k - 1) (MkBang n :: acc)

dedup : LList (!* Int) -@ LList (!* Int)
dedup [] = []
dedup (MkBang x :: []) = MkBang x :: []
dedup (MkBang x :: MkBang y :: rest) =
  if x == y then dedup (MkBang y :: rest) else MkBang x :: dedup (MkBang y :: rest)

render : (1 xs : LList (!* Int)) -> String -> String
render [] acc = acc
render (MkBang x :: xs) acc = render xs (acc ++ show x ++ " ")

count : (1 xs : LList (!* Int)) -> Int -> Int
count [] n = n
count (MkBang _ :: xs) n = count xs (n + 1)

drain : LList (!* Int) -@ ()
drain [] = ()
drain (MkBang _ :: xs) = drain xs

-- Whether each value is above the one before it.
increasing : Int -> (1 xs : LList (!* Int)) -> Bool
increasing _ [] = True
increasing prev (MkBang x :: xs) = if x <= prev then let 1 () = drain xs in False else increasing x xs

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
  putStrLn (render (dedup (build (n `div` 12500) 2 [])) "")
  printLn (count (dedup (build n 1 [])) 0)
  printLn (increasing 0 (dedup (build n 1 [])))
  printLn (increasing 0 (build n 1 []))
