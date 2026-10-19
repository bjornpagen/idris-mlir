module Main

-- A counter in an IORef: base's newIORef, modifyIORef, readIORef and
-- writeIORef, the one cell of an array of rank 0 read and written in the
-- world's order. The sum of 1 to n, n read (0 leaves the first value),
-- then a value written over it.

import Prelude
import Data.IORef

count : IORef Int -> Int -> IO ()
count ref n =
  if n <= 0 then pure ()
  else do modifyIORef ref (+ n)
          count ref (n - 1)

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
  ref <- newIORef 0
  count ref n
  readIORef ref >>= printLn
  writeIORef ref 7
  readIORef ref >>= printLn
