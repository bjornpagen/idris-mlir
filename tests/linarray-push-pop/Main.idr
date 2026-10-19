module Main

-- A stack on a growable linear vector. Pushes onto an empty vector grow
-- it past its capacity to cells at least twice as long and at least 4.
-- Pops then empty it, and one more pop gives Nothing: the size is the
-- vector's type, so a pop takes a vector with an element, and the stack
-- says Nothing when its size is 0. How many pushes there are is data, so
-- each loop gives back the size it ends at with the vector. The vector
-- frozen at the end has the size's elements, not the capacity's.

import Prelude
import Linear.Notation
import Array
import Linear.Vec

-- A vector whose size the data decides, with that size.
Stack : Type
Stack = Res Nat (\k => Vec k Int)

-- The size and the capacity, with the vector given back.
dims : (1 _ : Vec n Int) -> Res (Nat, Nat) (const (Vec n Int))
dims a = let s # a1 = size a
             c # a2 = capacity a1
         in (s, c) # a2

-- i * i pushed for each i from `i` below `n`, with the size and the
-- capacity after each push.
pushSquares : {k : Nat} -> (1 _ : Vec k Int) -> Int -> Int -> List (Nat, Nat) -> Res (List (Nat, Nat)) (const Stack)
pushSquares a i n acc =
  if i >= n then reverse acc # (k # a)
  else let d # a1 = dims (push a (i * i)) in pushSquares a1 (i + 1) n (d :: acc)

-- `j` pops, with what each gave: Nothing once the stack is empty.
drain : {k : Nat} -> (1 _ : Vec k Int) -> Int -> List (Maybe Int) -> Res (List (Maybe Int)) (const Stack)
drain {k = Z} a j acc =
  if j <= 0 then reverse acc # (Z # a) else drain a (j - 1) (Nothing :: acc)
drain {k = S m} a j acc =
  if j <= 0 then reverse acc # (S m # a)
  else let x # a1 = pop a in drain a1 (j - 1) (Just x :: acc)

readInt : IO Int
readInt = go 0
  where
    go : Int -> IO Int
    go acc = do
      c <- getChar
      if isDigit c then go (acc * 10 + cast (ord c - 48)) else pure acc

run : Int -> (List (Nat, Nat), List (Maybe Int), (Nat, Nat), Nat)
run n = unrestricted $ withVec 0 (the Int 0) (\a0 =>
  let ds # (_ # a1) = pushSquares a0 0 n []
      xs # (_ # a2) = drain a1 (n + 1) []
      d # a3 = dims a2
      MkBang f = Vec.freeze a3
  in MkBang (ds, xs, d, volume (shape f)))

main : IO ()
main = do
  n <- readInt
  let (ds, xs, d, frozen) = run n
  printLn ds
  printLn xs
  printLn d
  printLn frozen
