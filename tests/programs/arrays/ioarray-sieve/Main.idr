-- A sieve of Eratosthenes on an IOArray: the array primitives through
-- base's Data.IOArray, read and written in a loop.
module Main

import Prelude
import Data.IOArray

readInt : IO Int
readInt = go 0
  where
    go : Int -> IO Int
    go acc = do
      c <- getChar
      if c >= '0' && c <= '9' then go (acc * 10 + cast (ord c - ord '0')) else pure acc

mark : IOArray Bool -> Int -> Int -> Int -> IO ()
mark arr n p i =
  if i > n then pure ()
  else do ignore (writeArray arr i False)
          mark arr n p (i + p)

sieve : IOArray Bool -> Int -> Int -> IO ()
sieve arr n p =
  if p * p > n then pure ()
  else do Just isPrime <- readArray arr p
            | Nothing => pure ()
          when isPrime (mark arr n p (p * p))
          sieve arr n (p + 1)

count : IOArray Bool -> Int -> Int -> Int -> IO Int
count arr n i acc =
  if i > n then pure acc
  else do Just b <- readArray arr i
            | Nothing => count arr n (i + 1) acc
          count arr n (i + 1) (if b then acc + 1 else acc)

fill : IOArray Bool -> Int -> Int -> IO ()
fill arr n i = if i > n then pure () else do ignore (writeArray arr i True); fill arr n (i + 1)

main : IO ()
main = do
  n <- readInt
  arr <- newArray (n + 1)
  fill arr n 2
  sieve arr n 2
  c <- count arr n 2 0
  putStrLn (show c)
