module Main

-- A pop takes the last element out of a growable linear vector and puts
-- the fill back in its slot, so the vector keeps no reference to what it
-- gave, and a push after it stores in that slot again with no growth. The
-- elements are strings made at run time, each a cell of its own, so a
-- reference left behind would still be live at the end. The vector frozen
-- at the end holds its size's elements, in order.

import Prelude
import Linear.Notation
import Array
import Linear.Vec

-- The size and the capacity, with the vector given back.
dims : (1 _ : Vec n String) -> Res (Nat, Nat) (const (Vec n String))
dims a = let s # a1 = size a
             c # a2 = capacity a1
         in (s, c) # a2

-- Three pushes, a pop, a push, a pop and two pushes, each element the word
-- and a number; what the pops gave, the size and the capacity, and the
-- elements left.
run : String -> (List (Maybe String), (Nat, Nat), List String)
run w = unrestricted $ withVec 0 (the String "") (\v0 =>
  let v1 = push (push (push v0 (w ++ "-1")) (w ++ "-2")) (w ++ "-3")
      x # v2 = pop v1
      v3 = push v2 (w ++ "-4")
      y # v4 = pop v3
      v5 = push (push v4 (w ++ "-5")) (w ++ "-6")
      d # v6 = dims v5
      MkBang f = Vec.freeze v6
  in MkBang ([Just x, Just y], d, toList f))

main : IO ()
main = do
  w <- getLine
  let (popped, d, left) = run w
  printLn popped
  printLn d
  printLn left
