module Main

-- An array of a negative size is empty. Its first element is read when the
-- size is not 0, which a negative size is not: the access is outside the
-- array. Were the length the size itself, the size not 0 would prove index
-- 0 within it; the length is the size at least 0, so the access keeps its
-- check and ends the program there, after the output before it.

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

first : Arr -> IO Int
first arr = if size arr == 0 then pure 0 else primIO (prim__arrayGet (content arr) 0)

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
  arr <- newArr (0 - n)
  printLn (size arr)
  printLn !(first arr)
