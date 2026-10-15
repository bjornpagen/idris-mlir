module Main

-- Room reserved on a growable linear vector, then filled by pushes. A
-- reservation the capacity already has, none at all included, changes
-- nothing; one it has not grows the cells to at least twice their length,
-- or to the size and the room asked when that is more, the new slots
-- holding the fill. Pushes into the room grow nothing, and the push past
-- it doubles. The vector frozen at the end is its elements alone.

import Prelude
import Linear.Notation
import Array
import Linear.Vec

-- The size and the capacity, with the vector given back.
dims : (1 _ : Vec Int) -> Res (Nat, Nat) (const (Vec Int))
dims a = let s # a1 = size a
             c # a2 = capacity a1
         in (s, c) # a2

-- Each of `i` to `n` pushed, in order.
pushFrom : (1 _ : Vec Int) -> Int -> Int -> Vec Int
pushFrom a i n = if i > n then a else pushFrom (push a i) (i + 1) n

-- The size, the sum, the first element and the last.
frozen : (k : Nat) -> Vector k Int -> List Int
frozen k f =
  [cast k, sum f, fromMaybe 0 (f !? [<0]), fromMaybe 0 (f !? [<natToInteger k - 1])]

readInt : IO Int
readInt = go 0
  where
    go : Int -> IO Int
    go acc = do
      c <- getChar
      if isDigit c then go (acc * 10 + cast (ord c - 48)) else pure acc

run : Int -> (List (Nat, Nat), List Int)
run k = unrestricted $ withVec 3 (the Int 7) (\v =>
  let d0 # a0 = dims v
      d1 # a1 = dims (reserve a0 1)
      d2 # a2 = dims (reserve a1 3)
      d3 # a3 = dims (reserve a2 (cast (the Int (-5))))
      d4 # a4 = dims (reserve a3 (cast k))
      d5 # a5 = dims (pushFrom a4 1 k)
      d6 # a6 = dims (push a5 (k + 1))
      MkBang (n ** f) = Vec.freeze a6
  in MkBang ([d0, d1, d2, d3, d4, d5, d6], frozen n f))

main : IO ()
main = do
  k <- readInt
  let (ds, xs) = run k
  traverse_ printLn ds
  printLn xs
