module Main

-- Three IO functions that call one another in tail position, through an
-- if, a case and a with: a million calls, on the 1 MiB stack the harness
-- gives.

import Prelude

readInt : IO Int
readInt = go 0
  where
    go : Int -> IO Int
    go acc = do
      c <- getChar
      if isDigit c then go (acc * 10 + cast (ord c - 48)) else pure acc

mutual
  ping : Int -> Int -> IO Int
  ping n acc = if n <= 0 then pure acc else pong (n - 1) (acc + 1)

  pong : Int -> Int -> IO Int
  pong n acc = case n `mod` 3 of
    0 => ping (n - 1) (acc + 2)
    1 => pang (n - 1) acc
    _ => ping (n - 1) (acc + 3)

  pang : Int -> Int -> IO Int
  pang n acc with (n > 0)
    pang n acc | True = do
      when (n `mod` 250000 == 0) (printLn n)
      ping n acc
    pang n acc | False = pure acc

main : IO ()
main = do
  n <- readInt
  r <- ping n 0
  printLn r
