module Main

-- A write at the slot a pop left. The vector keeps its capacity, and the
-- slot its element, but the slot is past the size now, so the write is out
-- of bounds and ends the program after what was printed before it. A write
-- below the size is read back.

import Prelude
import Linear.Notation
import Array
import Linear.Vec

-- i + 10 pushed for each i from `i` below `n`.
pushTo : (1 _ : Vec Int) -> Int -> Int -> Vec Int
pushTo a i n = if i >= n then a else pushTo (push a (i + 10)) (i + 1) n

discard : (1 _ : Vec Int) -> ()
discard a = let MkBang _ = Vec.freeze a in ()

-- What a pop off `n` pushes gives, and the size and the capacity after it.
popped : Int -> (Maybe Int, (Nat, Nat))
popped n = unrestricted $ withVec 0 (the Int 0) (\a =>
  let x # a1 = pop (pushTo a 0 n)
      s # a2 = size a1
      c # a3 = capacity a2
      () = discard a3
  in MkBang (x, (s, c)))

-- 99 written at `i` after the pop, and read back.
rewritten : Int -> Nat -> Int
rewritten n i = unrestricted $ withVec 0 (the Int 0) (\a =>
  let _ # a1 = pop (pushTo a 0 n)
      x # a2 = Vec.read (Vec.write a1 i 99) i
      () = discard a2
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
  printLn (popped n)
  printLn (rewritten n (cast (n - 2)))
  printLn (rewritten n (cast (n - 1)))
