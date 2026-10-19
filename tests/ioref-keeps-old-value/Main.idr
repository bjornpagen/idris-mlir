module Main

-- A record read out of an IORef and kept while a changed copy is written
-- back: the read's next IO is the write, so the read takes the cell's
-- reference over, but the record is still used after the rebuild, which
-- must then build the copy in a cell of its own. The kept record and the
-- written one differ.

import Prelude
import Data.IORef

-- `next` makes Pair a box, a cell of its own, which the IORef holds a
-- reference to, so there is a cell a rebuild could take.
record Pair where
  constructor MkPair
  left : Int
  right : Int
  next : Maybe Pair

readInt : IO Int
readInt = go 0
  where
    go : Int -> IO Int
    go acc = do
      c <- getChar
      if c >= '0' && c <= '9' then go (acc * 10 + cast (ord c - ord '0')) else pure acc

main : IO ()
main = do
  n <- readInt
  ref <- newIORef (MkPair n (n * 2) Nothing)
  old <- readIORef ref
  writeIORef ref ({ left := old.left + 10 } old)
  new <- readIORef ref
  printLn old.left
  printLn new.left
  printLn (old.right + new.right)
