module Main

-- The first and last elements of an IOArray, read once its size is above
-- 0, and a fill below the size. base's readArray and writeArray test each
-- index against the size they keep beside the array; that size is the
-- length the array was made with, so those tests prove each access within
-- the array, and the access's own check is gone.

import Prelude
import Data.IOArray

ends : IOArray Int -> IO Int
ends arr =
  if 0 < max arr
    then do Just a <- readArray arr 0
              | Nothing => pure 0
            Just b <- readArray arr (max arr - 1)
              | Nothing => pure 0
            pure (a + b)
    else pure (-1)

fill : IOArray Int -> Int -> IO ()
fill arr i =
  if i >= max arr then pure ()
  else do ignore (writeArray arr i (i * i))
          fill arr (i + 1)

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
  arr <- newArray n
  fill arr 0
  printLn !(ends arr)
  empty <- newArray (n - n)
  printLn !(ends empty)
