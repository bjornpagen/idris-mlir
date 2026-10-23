module Main

-- Two functions that call each other in tail position, one returning an
-- array whose length its type fixes at 4, the other one whose length is
-- its argument n, called at 4: each returns what the other gives back, an
-- array of length 4 at a type that knows it and at one that does not. A
-- cast between the two after a call would be work after it, and the call
-- would no longer be the last thing its caller does. Ten million turns,
-- each a jump, and the array comes back as it was given.

import Prelude
import Array

-- A position as the Int the program computes with.
at : Fin n -> Int
at i = cast (finToNat i)

mutual
  fours : Int -> Array [<4] Int -> Array [<4] Int
  fours 0 x = x
  fours k x = step 4 (k - 1) x

  step : (n : Nat) -> Int -> Array [<n] Int -> Array [<n] Int
  step 4 k x = fours k x
  step _ _ x = x

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
  printLn (toList (fours k (tabulate [<4] (\[<i] => k + at i))))
