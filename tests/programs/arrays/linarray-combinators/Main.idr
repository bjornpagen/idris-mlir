module Main

-- The loops over an array's index space of Linear.Array (generate, imap,
-- map, zipWith, ifoldl, foldl, sum), each over an array of words, which
-- this compiler runs as one linalg operation, and which must compute what
-- the library's own definitions compute. The last one, over an array of
-- pairs, compiles as the library writes it: the same loop in Idris.

import Prelude
import Data.List
import Linear.Notation
import Linear.Array

-- squares[i] = i * i.
squares : Int -> Array Int
squares n = generate n (\i => i * i)

-- The sum of the squares below n: an ordered fold over the frozen array.
sumSquares : Int -> Int
sumSquares n = freeze (squares n) sum

halves : Int -> Array Double
halves n = generate n (\i => cast i + 0.5)

inverses : Int -> Array Double
inverses n = generate n (\i => 1.0 / cast (i + 1))

-- The dot product of two vectors: zipWith, then the sum in index order.
dot : Int -> Double
dot n = freeze (halves n) (\u => freeze (inverses n) (\v => freeze (zipWith (*) u v) sum))

-- Each square doubled (map), then its index added (imap), then weighed by
-- its index in the fold (ifoldl).
weighted : Int -> Int
weighted n =
  freeze (squares n) (\a =>
    freeze (map (* 2) a) (\doubled =>
      freeze (imap (\i, x => x + i) doubled) (ifoldl (\acc, i, x => acc + i * x) 0)))

-- A fold whose accumulator is a Double over Ints.
average : Int -> Double
average n = freeze (squares n) (\a => foldl (\acc, x => acc + cast x) 0.0 a / cast n)

-- An element that is not a word: a pair of Ints.
pairs : Int -> Int
pairs n = freeze (generate n (\i => (i, i * i))) (foldl (\acc, (x, y) => acc + x + y) 0)

-- x with d decimals, for a non-negative x.
fixed : Nat -> Double -> String
fixed d x =
  let scale = cast {to = Int} (pow 10.0 (cast d))
      s = cast {to = Int} (x * cast scale + 0.5)
      frac = show (s `mod` scale)
  in show (s `div` scale) ++ "." ++ pack (replicate (minus d (length frac)) '0') ++ frac

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
  printLn (sumSquares n)
  putStrLn (fixed 6 (dot n))
  printLn (weighted n)
  putStrLn (fixed 6 (average n))
  printLn (pairs n)
