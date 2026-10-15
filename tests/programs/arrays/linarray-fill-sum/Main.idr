module Main

-- A growable linear vector filled, then summed: pure code over
-- Linear.Vec, the vector threaded through every write and read at
-- quantity 1, which this compiler runs as one array cell and loops of
-- stores and loads.

import Prelude
import Linear.Notation
import Array
import Linear.Vec

fill : (1 _ : Vec Int) -> Nat -> Nat -> Vec Int
fill a n i = if i >= n then a else fill (Vec.write a i (cast i * 3)) n (S i)

sumTo : (1 _ : Vec Int) -> Nat -> Nat -> Int -> Res Int (const (Vec Int))
sumTo a n i acc =
  if i >= n then acc # a
  else let v # a' = Vec.read a i in sumTo a' n (S i) (acc + v)

readInt : IO Int
readInt = go 0
  where
    go : Int -> IO Int
    go acc = do
      c <- getChar
      if isDigit c then go (acc * 10 + cast (ord c - 48)) else pure acc

-- The sum of the filled vector, plus its first element and its size read
-- after it is frozen.
compute : Nat -> Int
compute n = unrestricted $ withVec n (the Int 0) $ \a =>
  let s # a' = sumTo (fill a n 0) n 0 0
      MkBang (k ** frozen) = Vec.freeze a'
  in MkBang (s + fromMaybe 0 (frozen !? [<0]) + cast k)

main : IO ()
main = do
  n <- readInt
  printLn (compute (cast n))
