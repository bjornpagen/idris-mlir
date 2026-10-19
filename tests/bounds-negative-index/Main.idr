module Main

-- An array beside its size, read under a test of the size alone: an index
-- below 0 passes it. Nothing proves that access within the array, so it
-- keeps its check and ends the program there, after the output before it.

import Prelude
import Data.IOArray.Prims

record Arr where
  constructor MkArr
  size : Int
  content : ArrayData Int

newArr : Int -> IO Arr
newArr n = do
  c <- primIO (prim__newArray n 7)
  pure (MkArr n c)

readAt : Arr -> Int -> IO Int
readAt arr i = if i >= size arr then pure 0 else primIO (prim__arrayGet (content arr) i)

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
  arr <- newArr n
  printLn !(readAt arr 0)
  printLn !(readAt arr (0 - n))
