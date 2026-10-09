module Main

-- A read at the size of a grown array, inside its backing, which has room
-- for three more. The slot is there, but no element is: the index is out
-- of bounds as an index past the backing is, and ends the program after
-- what was printed before it.

import Prelude
import Linear.Notation
import Linear.Array

-- i + 10 pushed for each i from `i` below `n`.
pushTo : (1 _ : Array Int) -> Int -> Int -> Array Int
pushTo a i n = if i >= n then a else pushTo (push a (i + 10)) (i + 1) n

-- The size and the capacity of `n` pushes onto an empty array.
dims : Int -> (Int, Int)
dims n = let s # a1 = size (pushTo (mkArray 0 0) 0 n)
             c # _ = capacity a1
         in (s, c)

readAt : Int -> Int -> Int
readAt n i = let x # _ = read (pushTo (mkArray 0 0) 0 n) i in x

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
  printLn (dims n)
  printLn (readAt n (n - 1))
  printLn (readAt n n)
