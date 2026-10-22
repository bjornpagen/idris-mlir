module Main

import Prelude

-- Two actions that call each other under a bind, a million levels deep:
-- report writes a line every 250,000 levels and countDown writes nothing,
-- so their own effects differ, yet both are one recursion, and each level
-- waits on the level under it. Its depth is kept in frames, never on the
-- native stack, whatever each member does.

mutual
  countDown : Int -> IO Int
  countDown 0 = pure 0
  countDown n = do
    r <- report (n - 1)
    pure (r + 1)

  report : Int -> IO Int
  report n = do
    when (n `mod` 250000 == 0) (putStrLn (show n))
    countDown n

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
  r <- countDown n
  printLn r
