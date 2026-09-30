module Main

import Prelude

-- A non-tail recursion a million calls deep, as deep as the number on
-- stdin: more frames than the 8 MiB stack a process gets by default holds,
-- and far fewer than the gibibyte the program's entry reserves for it.
depth : Int -> Int
depth 0 = 0
depth n = let r = depth (n - 1) in if r > n then r - n else r + n

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
  printLn (depth n)
