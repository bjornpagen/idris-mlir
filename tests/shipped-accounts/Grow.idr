module Main

-- Prints Grown, the module of the large case: the family Tree, and grown,
-- which takes apart each cell of its list and, before it builds the cell
-- again, makes a complete tree of Node cells `depth` levels deep over the
-- element it took out, every leaf that element. A Node cell is not a list
-- cell's size, so grown holds the cell it took apart, as a reuse token,
-- while the tree is made: its frame bound is a list cell's bytes, not
-- zero. The tree is written out in grown's one clause, each node with a
-- number of its own, so no two nodes are one value and none is static
-- data: some two thousand cells made, each a call, a store for each field
-- and an increment of the element, so that grown is past the size at
-- which a program function calls the runtime instead of inlining it,
-- which the run checks rather than assumes. grown recurses, so it stays a
-- function of its own.

import Prelude

%default total

depth : Nat
depth = 11

-- The tree of `d` levels under the node numbered `k`: a node's children
-- are numbered 2k and 2k + 1, so every node's number is its own.
tree : Nat -> Int -> String
tree Z _ = "t"
tree (S d) k = "(Node " ++ tree d (2 * k) ++ " " ++ show k ++ " " ++ tree d (2 * k + 1) ++ ")"

main : IO ()
main =
  traverse_ putStrLn
    [ "module Grown"
    , ""
    , "import Prelude"
    , ""
    , "public export"
    , "data Tree = Leaf | Node Tree Int Tree"
    , ""
    , "export"
    , "grown : List Tree -> List Tree"
    , "grown [] = []"
    , "grown (t :: ts) = " ++ tree depth 1 ++ " :: grown ts" ]
