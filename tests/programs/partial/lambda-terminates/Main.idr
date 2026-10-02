module Main

-- Idris reports termination per definition: main is partial, because the
-- loop it runs reading input has no decreasing argument. The lambda it
-- passes to traverse_ reaches only functions Idris proved terminating, so
-- the lifted function is total on its own, where copying main's fact would
-- make it partial and keep every call of it from moving.

import Prelude

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
  traverse_ (\x => printLn (x + n)) [1, 2, 3]
