module Main

-- A function's fact is about its own loops, as Idris's size-change graphs
-- show them. main loops itself, reading again when the number is large,
-- and nothing decreases round that loop, so main is not proved to
-- terminate (readInt's go is not either; readInt itself has no loop). The
-- lambda main passes to traverse_ has no loop of its own, so the lifted
-- function is total on its own, where copying main's fact would make it
-- partial and keep every call of it from moving; it reaches only
-- functions Idris proved terminating, so idr-effects finds that it does
-- not diverge.

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
  when (n > 100) main
