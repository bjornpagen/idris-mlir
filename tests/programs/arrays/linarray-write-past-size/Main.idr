module Main

-- A write at the slot a pop left. The array keeps its capacity, and the
-- slot its element, but the slot is past the size now, so the write is out
-- of bounds and ends the program after what was printed before it. A write
-- below the size is read back.

import Prelude
import Linear.Notation
import Linear.Array

-- i + 10 pushed for each i from `i` below `n`.
pushTo : (1 _ : Array Int) -> Int -> Int -> Array Int
pushTo a i n = if i >= n then a else pushTo (push a (i + 10)) (i + 1) n

-- What a pop off `n` pushes gives, and the size and the capacity after it.
popped : Int -> (Maybe Int, (Int, Int))
popped n = let x # a1 = pop (pushTo (mkArray 0 0) 0 n)
               s # a2 = size a1
               c # _ = capacity a2
           in (x, (s, c))

-- 99 written at `i` after the pop, and read back.
rewritten : Int -> Int -> Int
rewritten n i = let _ # a1 = pop (pushTo (mkArray 0 0) 0 n)
                    x # _ = read (write a1 i 99) i
                in x

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
  printLn (popped n)
  printLn (rewritten n (n - 2))
  printLn (rewritten n (n - 1))
