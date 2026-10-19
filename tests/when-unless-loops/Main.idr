module Main

-- Loops written with when and unless: the recursive call is the action
-- they run when the condition holds, in tail position of the function.
-- A million iterations each, on the 1 MiB stack the harness gives.

import Prelude

readInt : IO Int
readInt = go 0
  where
    go : Int -> IO Int
    go acc = do
      c <- getChar
      if isDigit c then go (acc * 10 + cast (ord c - 48)) else pure acc

upward : Int -> Int -> IO ()
upward n i = when (i < n) $ do
  when (i `mod` 250000 == 0) (printLn i)
  upward n (i + 1)

downward : Int -> IO ()
downward i = unless (i <= 0) $ do
  when (i `mod` 250000 == 0) (printLn i)
  downward (i - 1)

main : IO ()
main = do
  n <- readInt
  upward n 0
  downward n
