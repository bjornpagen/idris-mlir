module Main

-- An IORef of functions: each step writes back the function it read,
-- composed with one more increment, and the last is applied. What a read
-- of the IORef may give is every function made into it or written over
-- it, so the closures in it become one sum that its reads and writes
-- share. The number of steps is read, so that none is a constant: 0
-- leaves the identity the IORef was made with.

import Prelude
import Data.IORef

compose : IORef (Int -> Int) -> Int -> IO ()
compose ref n =
  if n <= 0 then pure ()
  else do modifyIORef ref (\f => f . (+ 1))
          compose ref (n - 1)

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
  ref <- newIORef id
  compose ref n
  f <- readIORef ref
  printLn (f 0)
  printLn (f 5)
