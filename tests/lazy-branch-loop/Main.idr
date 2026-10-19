module Main

-- A loop in IO whose recursion is the `else` of an `if`. Idris passes
-- both branches of an `if` as `Lazy`, and forces the one the condition
-- picks after the match.

import Prelude
import Data.IOArray

get : IOArray Int -> Int -> IO Int
get arr i = do
  Just v <- readArray arr i
    | Nothing => pure 0
  pure v

set : IOArray Int -> Int -> Int -> IO ()
set arr i v = ignore (writeArray arr i v)

-- count[i] := i mod 3 for i below n.
fill : IOArray Int -> Int -> Int -> IO ()
fill count n i = if i >= n then pure () else do set count i (i `mod` 3); fill count n (i + 1)

-- The first index from r on whose count is above 1, taking one from the
-- count of each index it reads; nothing once it reaches n.
next : Int -> IOArray Int -> Int -> IO (Maybe Int)
next n count r =
  if r == n
     then pure Nothing
     else do c <- get count r
             set count r (c - 1)
             if c > 1 then pure (Just r) else next n count (r + 1)

main : IO ()
main = do
  c <- getChar
  let n = cast (ord c - ord '0')
  count <- newArray n
  fill count n 0
  a <- next n count 1
  b <- next n count 1
  printLn (a, b)
