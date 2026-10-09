module Main

-- Room reserved on a linear array, then filled by pushes. A reservation
-- the capacity already has, a non-positive one included, changes nothing;
-- one it has not grows the backing to at least twice its length, or to
-- the size and the room asked when that is more, its new slots holding
-- the fill. Pushes into the room grow nothing, and the push past it
-- doubles. The array frozen at the end is its elements alone.

import Prelude
import Linear.Notation
import Linear.Array

-- The size and the capacity, with the array given back.
dims : (1 _ : Array Int) -> Res (Int, Int) (const (Array Int))
dims a = let s # a1 = size a
             c # a2 = capacity a1
         in (s, c) # a2

-- Each of `i` to `n` pushed, in order.
pushFrom : (1 _ : Array Int) -> Int -> Int -> Array Int
pushFrom a i n = if i > n then a else pushFrom (push a i) (i + 1) n

-- The size, the sum, the first element and the last.
frozen : IArray Int -> List Int
frozen f = [isize f, Linear.Array.sum f, iread f 0, iread f (isize f - 1)]

readInt : IO Int
readInt = go 0
  where
    go : Int -> IO Int
    go acc = do
      c <- getChar
      if isDigit c then go (acc * 10 + cast (ord c - 48)) else pure acc

run : Int -> (List (Int, Int), List Int)
run k =
  let d0 # a0 = dims (mkArray 3 7)
      d1 # a1 = dims (reserve a0 1 0)
      d2 # a2 = dims (reserve a1 3 0)
      d3 # a3 = dims (reserve a2 (-5) 0)
      d4 # a4 = dims (reserve a3 k 0)
      d5 # a5 = dims (pushFrom a4 1 k)
      d6 # a6 = dims (push a5 (k + 1))
  in ([d0, d1, d2, d3, d4, d5, d6], freeze a6 frozen)

main : IO ()
main = do
  k <- readInt
  let (ds, xs) = run k
  traverse_ printLn ds
  printLn xs
