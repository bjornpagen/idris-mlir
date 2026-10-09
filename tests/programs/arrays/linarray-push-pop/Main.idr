module Main

-- A stack on a linear array that grows. Pushes onto an empty array grow it
-- past its capacity to a backing at least twice as long and at least 4.
-- Pops then empty it, and one more pop gives Nothing. The array frozen at
-- the end has the size's elements, not the capacity's.

import Prelude
import Linear.Notation
import Linear.Array

-- The size and the capacity, with the array given back.
dims : (1 _ : Array Int) -> Res (Int, Int) (const (Array Int))
dims a = let s # a1 = size a
             c # a2 = capacity a1
         in (s, c) # a2

-- i * i pushed for each i from `i` below `n`, with the size and the
-- capacity after each push.
grow : (1 _ : Array Int) -> Int -> Int -> List (Int, Int) -> Res (List (Int, Int)) (const (Array Int))
grow a i n acc =
  if i >= n then reverse acc # a
  else let d # a1 = dims (push a (i * i)) in grow a1 (i + 1) n (d :: acc)

-- `k` pops, with what each gave.
drain : (1 _ : Array Int) -> Int -> List (Maybe Int) -> Res (List (Maybe Int)) (const (Array Int))
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

run : Int -> (List (Int, Int), List (Maybe Int), (Int, Int), Int)
run n =
  let ds # a1 = grow (mkArray 0 0) 0 n []
      xs # a2 = drain a1 (n + 1) []
      d # a3 = dims a2
  in (ds, xs, d, freeze a3 isize)

main : IO ()
main = do
  n <- readInt
  let (ds, xs, d, frozen) = run n
  printLn ds
  printLn xs
  printLn d
  printLn frozen
