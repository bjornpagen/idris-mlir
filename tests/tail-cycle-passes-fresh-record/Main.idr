module Main

import Prelude

-- Two functions that call each other in tail position a million times,
-- each passing a record it has just built. The record dies at the call,
-- so it could live in the caller's frame; but a tail call replaces that
-- frame, so the record is never put there, and every call is a jump: the
-- stack does not grow, however deep the cycle runs.

record Acc where
  constructor MkAcc
  count : Int
  total : Int

mutual
  ping : Int -> Acc -> Acc
  ping 0 a = a
  ping n (MkAcc c t) = pong (n - 1) (MkAcc (c + 1) (t + n))

  pong : Int -> Acc -> Acc
  pong 0 a = a
  pong n (MkAcc c t) = ping (n - 1) (MkAcc (c + 1) (t - n))

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
  let MkAcc c t = ping n (MkAcc 0 0)
  printLn (c, t)
