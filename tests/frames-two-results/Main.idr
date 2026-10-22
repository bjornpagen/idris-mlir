module Main

import Prelude

-- An action that gives back two numbers, under a bind a million levels
-- deep: each level waits for the pair the level under it gives, then
-- gives its own. A frame holds what a level needs after the call, however
-- many results the call gives back.

stats : Int -> IO (Int, Int)
stats 0 = pure (0, 0)
stats n = do
  (c, s) <- stats (n - 1)
  pure (c + 1, s + (n `mod` 7))

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
  r <- stats n
  printLn r
