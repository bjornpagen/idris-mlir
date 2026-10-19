-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
module Main

-- thread-ring (the Benchmarks Game): 503 threads, named 1 to 503, stand in
-- a ring, each linked to the next and 503 to 1. Thread 1 is given a token,
-- the number n; a thread given the token passes it on to the next one
-- less one, and the thread given it at 0 prints its name. The game
-- specifies 503 threads; threads are outside this compiler's language, so
-- this is the same workload under a deterministic cooperative scheduler:
-- the ring is explicit state, the 503 threads' mailboxes in an array
-- (base's IOArray; slot i is thread i + 1's), and the scheduler visits the
-- threads round-robin in ring order. A thread whose mailbox is empty is
-- blocked on its receive and yields; one with the token in its mailbox
-- runs, takes it, and sends it on. The C in main.c is this algorithm too,
-- and its output is byte for byte this one's: the game's, n mod 503 + 1
-- (498 for n = 1000, 292 for the game's size, 50000000).

import Prelude
import Data.IOArray

threads : Int
threads = 503

-- The thread after slot i's, in the ring.
next : Int -> Int
next i = if i + 1 == threads then 0 else i + 1

-- Thread i + 1's mailbox, emptied: what it held, if anything.
receive : IOArray (Maybe Int) -> Int -> IO (Maybe Int)
receive ring i = do
  Just (Just token) <- readArray ring i
    | _ => pure Nothing
  ignore (writeArray ring i Nothing)
  pure (Just token)

send : IOArray (Maybe Int) -> Int -> Int -> IO ()
send ring i token = ignore (writeArray ring i (Just token))

-- The scheduler at slot i: runs the thread there if it can, then moves on
-- round the ring. The result is the name the thread given 0 prints.
schedule : IOArray (Maybe Int) -> Int -> IO Int
schedule ring i = do
  box <- receive ring i
  case box of
    Nothing => schedule ring (next i)
    Just 0 => pure (i + 1)
    Just token => do
      send ring (next i) (token - 1)
      schedule ring (next i)

-- Every mailbox from slot i on, empty.
empty : IOArray (Maybe Int) -> Int -> IO ()
empty ring i =
  if i >= threads then pure ()
  else do ignore (writeArray ring i Nothing)
          empty ring (i + 1)

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
  ring <- newArray threads
  empty ring 0
  send ring 0 n
  name <- schedule ring 0
  putStrLn (show name)
