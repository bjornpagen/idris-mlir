module Main

-- graft takes apart each cell of its list and makes a tree before it
-- builds the cell again, so it holds the cell it took apart, as a reuse
-- token, while the tree is made: a tree's cell is not a list cell's size,
-- so the token waits for the list cell. Its frame bound is a list cell's
-- bytes, not zero. graft recurses, so it stays a function of its own.
-- Grown, which the run prints from Grow.idr, holds Tree and grown, which
-- does the same around a tree of some two thousand cells: a function of
-- such a bound past the size at which it calls the runtime instead of
-- inlining it.

import Prelude
import Grown

graft : List Tree -> List Tree
graft [] = []
graft (t :: ts) = Node t 0 Leaf :: graft ts

plant : Int -> List Tree -> List Tree
plant 0 acc = acc
plant n acc = plant (n - 1) (Node Leaf n Leaf :: acc)

weigh : List Tree -> Int -> Int
weigh [] acc = acc
weigh (Node (Node _ v _) _ _ :: ts) acc = weigh ts (acc + v)
weigh (_ :: ts) acc = weigh ts acc

main : IO ()
main = do
  printLn (weigh (graft (plant 100 [])) 0)
  printLn (weigh (grown (plant 100 [])) 0)
