module Main

-- generate at sizes that are not positive, each an empty array: the least
-- Int, -1 and 0, from the input so that nothing is known of them when
-- compiling. At a word element this compiler makes the generate one loop;
-- at a pair it compiles the library's definition as written, which counts
-- the elements after the first in Integer, so that the least Int, whose
-- n - 1 wraps to the greatest Int, is empty too. A positive size last.

import Prelude
import Linear.Notation
import Linear.Array

sizes : Int -> (Int, Int)
sizes n = (freeze (generate n (\i => i * 2)) isize, freeze (generate n (\i => (i, i))) isize)

readInt : IO Int
readInt = go 0
  where
    go : Int -> IO Int
    go acc = do
      c <- getChar
      if isDigit c then go (acc * 10 + cast (ord c - 48)) else pure acc

main : IO ()
main = do
  k <- readInt
  m <- readInt
  let least = 0 - m - k
  printLn least
  printLn (sizes least)
  printLn (sizes (k - 2))
  printLn (sizes (k - 1))
  printLn (sizes (k + 2))
