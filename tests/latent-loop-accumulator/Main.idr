module Main

-- As eval/latent-loop, with an accumulator that grows by a cell at every
-- step: `next`'s raised clone is on no cycle of references, but it recurses
-- where `next` does, so its parameters have `next`'s binding times, and the
-- accumulator is no parameter to specialize on. Taken for a function on no
-- cycle, the clone was specialized on the list it was given, and then on
-- that list one cell longer, a clone more every round, until the round
-- budget ran out.

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

next : Int -> IOArray Int -> Int -> List Int -> IO (Maybe Int)
next n count r seen =
  if r == n then pure (Just (sum seen))
  else do c <- get count r
          set count r (c - 1)
          if c > 1 then pure (Just r) else after c (next n count (r + 1) (c :: seen))

main : IO ()
main = do
  c <- getChar
  let n = cast (ord c - ord '0')
  count <- newArray n
  fill count n 0
  a <- next n count 1 []
  b <- next n count 1 [7]
  c <- next n count 2 []
  printLn (a, b, c)
