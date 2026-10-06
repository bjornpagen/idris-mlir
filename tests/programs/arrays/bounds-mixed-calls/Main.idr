module Main

-- One function sums an array beside its size, testing each index against
-- the size as base's readArray does. It is called first with an array and
-- its own size, then with that array beside a size one larger: only the
-- first call passes a size that is the array's length, so the reads keep
-- their checks, and the second call ends the program at the index past the
-- array, after the first call's output.

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
readAt arr i =
  if i < 0 || i >= size arr then pure 0 else primIO (prim__arrayGet (content arr) i)

sumArr : Arr -> Int -> Int -> IO Int
sumArr arr i acc =
  if i >= size arr then pure acc
  else do v <- readAt arr i
          sumArr arr (i + 1) (acc + v)

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
  printLn !(sumArr arr 0 0)
  printLn !(sumArr (MkArr (n + 1) (content arr)) 0 0)
