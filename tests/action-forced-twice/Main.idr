module Main

-- A suspended IO action forced twice runs twice, each run from the start:
-- the action is a value that may be used many times, though the closure
-- inside it holds the linear halves of the binds it was built from. The
-- walk forces the rest of itself twice wherever a count is used up, and
-- `twice` forces one chain of binds twice in the branch of an `if`. The
-- counts the array ends with say how often each step ran.

import Prelude
import Data.IOArray

get : IOArray Int -> Int -> IO Int
get arr i = do
  Just v <- readArray arr i
    | Nothing => pure 0
  pure v

set : IOArray Int -> Int -> Int -> IO ()
set arr i v = ignore (writeArray arr i v)

fill : IOArray Int -> Int -> Int -> IO ()
fill count n i = if i >= n then pure () else do set count i (i `mod` 3); fill count n (i + 1)

next : Int -> IOArray Int -> Int -> IO (Maybe Int)
next n count r =
  if r == n
     then pure Nothing
     else do c <- get count r
             set count r (c - 1)
             let rest = the (Lazy (IO (Maybe Int))) (Delay (next n count (r + 1)))
             if c > 1 then pure (Just r) else (Force rest >>= \_ => Force rest)

-- Adds `by` to cell 0 and gives what it held.
bump : IOArray Int -> Int -> IO Int
bump arr by = do
  v <- get arr 0
  set arr 0 (v + by)
  pure v

twice : IOArray Int -> Int -> IO Int
twice arr k =
  let rest = the (Lazy (IO Int)) (Delay (bump arr k >>= \a => bump arr (a + 1))) in
  if k > 5 then pure k else (Force rest >>= \_ => Force rest)

counts : IOArray Int -> Int -> Int -> IO (List Int)
counts arr n i =
  if i >= n
     then pure []
     else do v <- get arr i
             vs <- counts arr n (i + 1)
             pure (v :: vs)

main : IO ()
main = do
  c <- getChar
  let n = cast (ord c - ord '0')
  count <- newArray n
  fill count n 0
  a <- next n count 1
  b <- next n count 1
  printLn (a, b)
  x <- twice count (n - 3)
  printLn x
  vs <- counts count n 0
  printLn vs
