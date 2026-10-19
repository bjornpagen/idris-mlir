module Main

-- `next` loops through the closures of its `do` block, and so is a loop
-- breaker. Its recursive call goes to `after`, which runs the action it is
-- given after k steps; only once `after` is unrolled at k = 0 does the call
-- meet the projection and apply that run it, and raising makes it a call of
-- `next`'s raised clone. Until then the clone is on no cycle of references,
-- but it recurses where `next` does, so its parameters have `next`'s
-- binding times. Taken for a function on no cycle, it was specialized on
-- the array, and the specialization, inlined, put the call of `next` back
-- into its caller, for which it was made again: the compilation unrolled
-- the loop once every two rounds, and never ended.

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

after : Int -> IO (Maybe Int) -> IO (Maybe Int)
after k rest = if k <= 0 then rest else after (k - 1) rest

next : Int -> IOArray Int -> Int -> IO (Maybe Int)
next n count r =
  if r == n then pure Nothing
  else do c <- get count r
          set count r (c - 1)
          if c > 1 then pure (Just r) else after c (next n count (r + 1))

main : IO ()
main = do
  c <- getChar
  let n = cast (ord c - ord '0')
  count <- newArray n
  fill count n 0
  a <- next n count 1
  b <- next n count 1
  printLn (a, b)
