module Main

-- A read at the size of a grown vector, inside its cells, which have room
-- for three more. The slot is there, but no element is: the index is out
-- of bounds as an index past the cells is, and ends the program after
-- what was printed before it.

import Prelude
import Linear.Notation
import Array
import Linear.Vec

-- i + 10 pushed for each i from `i` below `n`.
pushTo : (1 _ : Vec Int) -> Int -> Int -> Vec Int
pushTo a i n = if i >= n then a else pushTo (push a (i + 10)) (i + 1) n

discard : (1 _ : Vec Int) -> ()
discard a = let MkBang _ = Vec.freeze a in ()

-- The size and the capacity of `n` pushes onto an empty vector.
dims : Int -> (Nat, Nat)
dims n = unrestricted $ withVec 0 (the Int 0) (\a =>
  let s # a1 = size (pushTo a 0 n)
      c # a2 = capacity a1
      () = discard a2
  in MkBang (s, c))

readAt : Int -> Nat -> Int
readAt n i = unrestricted $ withVec 0 (the Int 0) (\a =>
  let x # a1 = Vec.read (pushTo a 0 n) i
      () = discard a1
  in MkBang x)

readInt : IO Int
readInt = go 0
  where
    go : Int -> IO Int
    go acc = do
      c <- getChar
      if isDigit c then go (acc * 10 + cast (ord c - 48)) else pure acc

main : IO ()
main = do
  n <- readInt
  printLn (dims n)
  printLn (readAt n (cast (n - 1)))
  printLn (readAt n (cast n))
