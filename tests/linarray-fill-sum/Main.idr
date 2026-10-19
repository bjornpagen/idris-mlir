module Main

-- A growable linear vector filled, then summed: pure code over
-- Linear.Vec, the vector threaded through every write and read at
-- quantity 1, which this compiler runs as one array cell and loops of
-- stores and loads.

import Prelude
import Data.So
import Linear.Notation
import Array
import Linear.Vec

fill : {n : Nat} -> (1 _ : Vec n Int) -> Nat -> Vec n Int
fill a i = case choose (i < n) of
  Left inside => fill (Vec.write a (natToFinLt i @{inside}) (cast i * 3)) (S i)
  Right _ => a

sumTo : {n : Nat} -> (1 _ : Vec n Int) -> Nat -> Int -> Res Int (const (Vec n Int))
sumTo a i acc = case choose (i < n) of
  Left inside => let v # a' = Vec.read a (natToFinLt i @{inside}) in sumTo a' (S i) (acc + v)
  Right _ => acc # a

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
  let s # a' = sumTo (fill a 0) 0 0
      MkBang frozen = Vec.freeze a'
  in MkBang (s + fromMaybe 0 (frozen !? [<0]) + cast (volume (shape frozen)))

main : IO ()
main = do
  n <- readInt
  printLn (compute (cast n))
