module Main

-- A recursion that returns its own result two constructors deep, each
-- element twice, is written top down through the destination of the inner
-- cell and runs in constant stack: a million elements, where the harness
-- gives a program a 1 MiB stack. The list is built by a tail-recursive
-- loop and summed by one, so what is tested is dup.

import Prelude

readInt : IO Int
readInt = go 0
  where
    go : Int -> IO Int
    go acc = do
      c <- getChar
      if isDigit c then go (acc * 10 + cast (ord c - 48)) else pure acc

build : Int -> List Int -> List Int
build 0 acc = acc
build n acc = build (n - 1) (n :: acc)

dup : List Int -> List Int
dup [] = []
dup (x :: xs) = x :: x :: dup xs

sum : List Int -> Int -> Int
sum [] acc = acc
sum (x :: xs) acc = sum xs (acc + x)

main : IO ()
main = do
  n <- readInt
  printLn (sum (dup (build n [])) 0)
