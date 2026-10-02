module Main

-- pidigits (the Benchmarks Game): the digits of pi from Gibbons's
-- unbounded spigot, ten to a line, on Idris's Integer. The IO loop binds a
-- closure whose captures are linear, matched from an unrestricted value:
-- the fields come out at the value's grade.

import Prelude
import Data.List

mutual
  digits : Int -> Int -> Integer -> Integer -> Integer -> Integer -> Int -> String -> IO ()
  digits wanted k n a d k1 i line =
    let k' = k + 1
        n1 = n * cast k'
        a1 = a + n * 2
        k1' = k1 + 2
        a2 = a1 * k1'
        d1 = d * k1'
    in if a2 >= n1
         then let s = n1 * 3 + a2
                  q = s `div` d1
                  u = s `mod` d1 + n1
              in if d1 > u then emit wanted k' n1 a2 d1 k1' i line q
                 else digits wanted k' n1 a2 d1 k1' i line
         else digits wanted k' n1 a2 d1 k1' i line

  emit : Int -> Int -> Integer -> Integer -> Integer -> Integer -> Int -> String -> Integer -> IO ()
  emit wanted k n a d k1 i line q = do
    let line' = line ++ show q
    let i' = i + 1
    let full = i' `mod` 10 == 0
    when full (putStrLn (line' ++ "\t:" ++ show i'))
    if i' >= wanted
      then when (not full)
             (putStrLn (line' ++ pack (replicate (cast (10 - i' `mod` 10)) ' ') ++ "\t:" ++ show i'))
      else digits wanted k (n * 10) ((a - d * q) * 10) d k1 i' (if full then "" else line')

readInt : IO Int
readInt = go 0
  where
    go : Int -> IO Int
    go acc = do
      c <- getChar
      if isDigit c then go (acc * 10 + cast (ord c - 48)) else pure acc

main : IO ()
main = do
  wanted <- readInt
  digits wanted 0 1 0 1 1 0 ""
