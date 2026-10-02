-- Partition list (LeetCode 86): the values below the pivot, then the rest,
-- each in their original order, on a linear list: both parts are built
-- from the input's cells, relinked.
module Main

import Prelude
import Linear.Notation
import Linear.List

build : Int -> Int -> LList (!* Int) -@ LList (!* Int)
build n seed acc =
  if n <= 0 then acc
  else let seed' = (seed * 1103515245 + 12345) `mod` 2147483648
       in build (n - 1) seed' (MkBang ((seed' `div` 65536) `mod` 100) :: acc)

rev : LList (!* Int) -@ LList (!* Int) -@ LList (!* Int)
rev [] acc = acc
rev (x :: xs) acc = rev xs (x :: acc)

part : Int -> LList (!* Int) -@ LList (!* Int) -@ LList (!* Int) -@ LList (!* Int)
part pivot [] small big = rev small (rev big [])
part pivot (MkBang x :: xs) small big =
  if x < pivot then part pivot xs (MkBang x :: small) big
  else part pivot xs small (MkBang x :: big)

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
  putStrLn (render (part 50 (build (n `div` 8000) 3 []) [] []) "")
  printLn (sumL (part 50 (build n 5 []) [] []) 0)
