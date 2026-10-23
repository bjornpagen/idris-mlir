module Main

-- A recursion in tail position that only computes gives back one of two
-- ways to build an array of four, and its caller builds the array with it
-- at once, at a type that fixes the length. So the building may move into
-- the recursion's tails: what then gives the array gives it at a type
-- that leaves its length to its extents, and the caller casts it back to
-- four after the call, where its own type states the length, never
-- between a call and a return. Ten million turns, each a jump, and the
-- array comes out with its four elements.

import Prelude
import Array

-- A position as the Int the program computes with.
at : Fin n -> Int
at i = cast (finToNat i)

-- k, k + 1, k + 2, k + 3.
rising : Int -> Array [<4] Int
rising k = tabulate [<4] (\[<i] => k + at i)

-- k + 3, k + 2, k + 1, k.
falling : Int -> Array [<4] Int
falling k = tabulate [<4] (\[<i] => k + 3 - at i)

-- Down two at a time: rising for an even count, falling for an odd one.
turn : Nat -> (Int -> Array [<4] Int)
turn Z = rising
turn (S Z) = falling
turn (S (S n)) = turn n

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
  let xs : Array [<4] Int = turn (cast k) k
  printLn (toList xs)
