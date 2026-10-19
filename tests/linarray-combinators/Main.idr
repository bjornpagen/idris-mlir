module Main

-- The generating set of typed arrays and the library code over it
-- (tabulate, map, zipWith, foldl, sum), each over an array of words, which
-- this compiler structures as linalg operations, and which must compute
-- what the library's own definitions compute. The last one is over an
-- array of pairs, a record element, which is one array per field.

import Prelude
import Data.List
import Array

-- A position as the Int the program computes with.
at : Fin n -> Int
at i = cast (finToNat i)

-- squares[i] = i * i.
squares : (n : Nat) -> Vector n Int
squares n = tabulate [<n] (\[<i] => at i * at i)

-- The sum of the squares below n: a left fold in index order.
sumSquares : Nat -> Int
sumSquares n = sum (squares n)

halves : (n : Nat) -> Vector n Double
halves n = tabulate [<n] (\[<i] => cast (at i) + 0.5)

inverses : (n : Nat) -> Vector n Double
inverses n = tabulate [<n] (\[<i] => 1.0 / cast (at i + 1))

-- The dot product of two vectors: zipWith, then the sum in index order.
dot : Nat -> Double
dot n = sum (zipWith (*) (halves n) (inverses n))

-- Each square doubled (map), then its index added, then weighed by its
-- index in the sum.
weighted : (n : Nat) -> Int
weighted n =
  let doubled = map (* 2) (squares n)
      indexed = tabulate [<n] (\[<i] => doubled !! [<i] + at i)
  in sum (tabulate [<n] (\[<i] => at i * indexed !! [<i]))

-- A fold whose accumulator is a Double over Ints.
average : Nat -> Double
average n = foldl (\acc, x => acc + cast x) 0.0 (squares n) / cast n

-- An element that is not a word: a pair of Ints.
pairs : (n : Nat) -> Int
pairs n = foldl (\acc, (x, y) => acc + x + y) 0 (tabulate [<n] (\[<i] => (at i, at i * at i)))

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
  k <- readInt
  let n = cast {to = Nat} k
  printLn (sumSquares n)
  putStrLn (fixed 6 (dot n))
  printLn (weighted n)
  putStrLn (fixed 6 (average n))
  printLn (pairs n)
