module Main

-- As eval/latent-loop, with the rest of the loop a suspension that a `let`
-- binds and the `else` of an `if` forces. The force meets the suspension,
-- its one use, so the branch calls `next`, and raising and specialization
-- on the array, which `next` passes on unchanged, make that call one of a
-- specialization of `next`'s raised clone. That clone runs `next`'s loop,
-- and breaks it where `next` does. Inlined first, it would put the call of
-- `next` back into its caller, for which specialization makes it again: the
-- compilation would unroll the loop once every two rounds, and never end.

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
             if c > 1 then pure (Just r) else rest

main : IO ()
main = do
  c <- getChar
  let n = cast (ord c - ord '0')
  count <- newArray n
  fill count n 0
  a <- next n count 1
  b <- next n count 1
  printLn (a, b)
