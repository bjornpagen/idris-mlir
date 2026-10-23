module Main

-- A recursion a million levels deep that subtracts after its call
-- returns, over an array whose length is an index of its type: each level
-- reads its element of the array once the level under it has given its
-- value. The code after the call becomes a function of its own, which
-- waits on the frame stack, and the length the type states of the array
-- that function takes is the length its caller's type states, by the same
-- index. Subtraction is no operation an accumulator may regroup, so the
-- depth stays on the frames.

import Prelude
import Array

-- A position as the Int the program computes with.
at : Fin n -> Int
at i = cast (finToNat i)

-- The element of xs at position i, 0 past its end.
element : Vector n Int -> Int -> Int
element xs i = case xs !? [<cast i] of
  Just v => v
  Nothing => 0

-- Minus the sum of the elements of xs below position k, the last
-- subtracted first.
fall : Vector n Int -> Int -> Int
fall xs k =
  if k <= 0 then 0
  else let below = fall xs (k - 1) in below - element xs (k - 1)

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
  printLn (fall (tabulate [<n] (\[<i] => at i + 1)) k)
