module Main

-- A record of a size and an array built by hand, the size of one array
-- beside another, shorter one. The read tests the index against the size
-- as base's readArray does, which says nothing of this array: the access
-- keeps its check and ends the program there, after the output before it.

import Prelude
import Data.IOArray.Prims

record Arr where
  constructor MkArr
  size : Int
  content : ArrayData Int

readAt : Arr -> Int -> IO Int
readAt arr i =
  if i < 0 || i >= size arr then pure 0 else primIO (prim__arrayGet (content arr) i)

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
  short <- primIO (prim__newArray (n - 2) 7)
  let arr = MkArr n short
  printLn !(readAt arr (n - 3))
  printLn !(readAt arr (n - 1))
