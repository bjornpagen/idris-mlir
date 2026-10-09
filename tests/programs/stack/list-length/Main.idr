module Main

-- A successor of a recursive result is an accumulator, so length is a
-- loop. The harness gives a 1 MiB stack: a hundred thousand elements would
-- keep a frame each. The element is an Int, so replicate writes each cell
-- in a loop already, and what is tested is length. The first line is a
-- short list; the second is the long list; the third is the count it was
-- built from.

import Prelude
import Data.List

readInt : IO Int
readInt = go 0
  where
    go : Int -> IO Int
    go acc = do
      c <- getChar
      if isDigit c then go (acc * 10 + cast (ord c - 48)) else pure acc

main : IO ()
main = do
  small <- readInt
  large <- readInt
  printLn (length (replicate (cast small) (the Int 0)))
  printLn (length (replicate (cast large) (the Int 0)))
  printLn large
