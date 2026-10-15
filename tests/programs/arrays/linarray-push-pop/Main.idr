module Main

-- A stack on a growable linear vector. Pushes onto an empty vector grow
-- it past its capacity to cells at least twice as long and at least 4.
-- Pops then empty it, and one more pop gives Nothing. The vector frozen at
-- the end has the size's elements, not the capacity's.

import Prelude
import Linear.Notation
import Array
import Linear.Vec

-- The size and the capacity, with the vector given back.
dims : (1 _ : Vec Int) -> Res (Nat, Nat) (const (Vec Int))
dims a = let s # a1 = size a
             c # a2 = capacity a1
         in (s, c) # a2

-- i * i pushed for each i from `i` below `n`, with the size and the
-- capacity after each push.
pushSquares : (1 _ : Vec Int) -> Int -> Int -> List (Nat, Nat) -> Res (List (Nat, Nat)) (const (Vec Int))
pushSquares a i n acc =
  if i >= n then reverse acc # a
  else let d # a1 = dims (push a (i * i)) in pushSquares a1 (i + 1) n (d :: acc)

-- `k` pops, with what each gave.
drain : (1 _ : Vec Int) -> Int -> List (Maybe Int) -> Res (List (Maybe Int)) (const (Vec Int))
drain a k acc =
  if k <= 0 then reverse acc # a
  else let x # a1 = pop a in drain a1 (k - 1) (x :: acc)

readInt : IO Int
readInt = go 0
  where
    go : Int -> IO Int
    go acc = do
      c <- getChar
      if isDigit c then go (acc * 10 + cast (ord c - 48)) else pure acc

run : Int -> (List (Nat, Nat), List (Maybe Int), (Nat, Nat), Nat)
run n = unrestricted $ withVec 0 (the Int 0) (\a0 =>
  let ds # a1 = pushSquares a0 0 n []
      xs # a2 = drain a1 (n + 1) []
      d # a3 = dims a2
      MkBang (k ** _) = Vec.freeze a3
  in MkBang (ds, xs, d, k))

main : IO ()
main = do
  n <- readInt
  let (ds, xs, d, frozen) = run n
  printLn ds
  printLn xs
  printLn d
  printLn frozen
