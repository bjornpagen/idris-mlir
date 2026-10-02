-- Reverse a linked list (LeetCode 206), on a linear list whose length is
-- read at run time, so that nothing is evaluated at compile time: the cells are
-- the output's, relinked in place; no cell is allocated or tested.
module Main

import Prelude
import Linear.Notation
import Linear.List

build : Int -> LList (!* Int) -@ LList (!* Int)
build n acc = if n <= 0 then acc else build (n - 1) (MkBang n :: acc)

rev : LList (!* Int) -@ LList (!* Int) -@ LList (!* Int)
rev [] acc = acc
rev (x :: xs) acc = rev xs (x :: acc)

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
