module Main

-- A write at the slot a pop left. The vector keeps its capacity, and the
-- slot holds the fill again, but the slot is past the size now: the size
-- is the vector's type, so a natural index is checked against it
-- (checkIndex) before it writes, and the program says what an index at or
-- past the size means. Here it prints that the index is out of range,
-- after what was printed before it. A write below the size is read back.

import Prelude
import Linear.Notation
import Array
import Linear.Vec

-- A vector whose size the data decides, with that size.
Sized : Type
Sized = Res Nat (\m => Vec m Int)

-- i + 10 pushed for each i from `i` below `n`.
pushTo : {k : Nat} -> (1 _ : Vec k Int) -> Int -> Int -> Sized
pushTo a i n = if i >= n then k # a else pushTo (push a (i + 10)) (i + 1) n

-- The last element taken off, when there is one, and the vector after.
popLast : {k : Nat} -> (1 _ : Vec k Int) -> Res (Maybe Int) (const Sized)
popLast {k = Z} a = Nothing # (Z # a)
popLast {k = S m} a = let x # a1 = pop a in Just x # (m # a1)

discard : (1 _ : Vec k Int) -> ()
discard a = let MkBang _ = Vec.freeze a in ()

-- What a pop off `n` pushes gives, and the size and the capacity after it.
popped : Int -> (Maybe Int, (Nat, Nat))
popped n = unrestricted $ withVec 0 (the Int 0) (\a =>
  let _ # a1 = pushTo a 0 n
      x # (_ # a2) = popLast a1
      s # a3 = size a2
      c # a4 = capacity a3
      () = discard a4
  in MkBang (x, (s, c)))

-- 99 written at `i` after the pop and read back, when `i` is below the
-- size.
rewritten : Int -> Nat -> Maybe Int
rewritten n i = unrestricted $ withVec 0 (the Int 0) (\a =>
  let _ # a1 = pushTo a 0 n
      _ # (m # a2) = popLast a1
  in case checkIndex m i of
       Just j => let x # a3 = Vec.read (Vec.write a2 j 99) j
                     () = discard a3
                 in MkBang (Just x)
       Nothing => let () = discard a2 in MkBang Nothing)

-- What a write read back, or that its index is out of range.
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
  printLn (popped n)
  let below = cast (n - 2)
  putStrLn (report below (rewritten n below))
  let past = cast (n - 1)
  putStrLn (report past (rewritten n past))
