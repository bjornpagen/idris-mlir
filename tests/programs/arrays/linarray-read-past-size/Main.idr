module Main

-- A read at the size of a grown vector, inside its cells, which have room
-- for three more. The slot is there, but no element is: the size is the
-- vector's type, so a natural index is checked against it (checkIndex)
-- before it reads, and the program says what an index at or past the size
-- means. Here it prints that the index is out of range, after what was
-- printed before it.

import Prelude
import Linear.Notation
import Array
import Linear.Vec

-- i + 10 pushed for each i from `i` below `n`: how many is data, so the
-- size comes back with the vector.
pushTo : {k : Nat} -> (1 _ : Vec k Int) -> Int -> Int -> Res Nat (\m => Vec m Int)
pushTo a i n = if i >= n then k # a else pushTo (push a (i + 10)) (i + 1) n

discard : (1 _ : Vec k Int) -> ()
discard a = let MkBang _ = Vec.freeze a in ()

-- The size and the capacity of `n` pushes onto an empty vector.
dims : Int -> (Nat, Nat)
dims n = unrestricted $ withVec 0 (the Int 0) (\a =>
  let _ # a1 = pushTo a 0 n
      s # a2 = size a1
      c # a3 = capacity a2
      () = discard a3
  in MkBang (s, c))

-- The element at `i` after `n` pushes, when `i` is below the size.
readAt : Int -> Nat -> Maybe Int
readAt n i = unrestricted $ withVec 0 (the Int 0) (\a =>
  let m # a1 = pushTo a 0 n in
  case checkIndex m i of
    Just j => let x # a2 = Vec.read a1 j
                  () = discard a2
              in MkBang (Just x)
    Nothing => let () = discard a1 in MkBang Nothing)

-- What a read gave, or that its index is out of range.
report : Nat -> Maybe Int -> String
report _ (Just x) = show x
report i Nothing = "index " ++ show i ++ " is out of range"

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
  let last = cast (n - 1)
  putStrLn (report last (readAt n last))
  let past = cast n
  putStrLn (report past (readAt n past))
