module Main

-- A loop carries an array beside its size and tests each index against the
-- size, as base's readArray does; but each time round it passes on the
-- size one larger and the same array. The size it starts with is the
-- array's length, the size it passes back is not, so the read keeps its
-- check and ends the program at the index past the array, after the
-- output before the loop.

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

walk : Arr -> Int -> Int -> IO Int
walk arr i acc =
  if i < 0 || i >= size arr then pure acc
  else do v <- primIO (prim__arrayGet (content arr) i)
          walk (MkArr (size arr + 1) (content arr)) (i + 1) (acc + v)

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
  printLn (size arr)
  printLn !(walk arr 0 0)
