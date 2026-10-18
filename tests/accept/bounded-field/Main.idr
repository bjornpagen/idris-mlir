module Main

import Prelude

-- A tree whose nodes hold named subtrees: T nm holds a List (String, T nm),
-- so showing a list of T Int shows each T Int, whose list of pairs shows a
-- String and a T Int again. The implementations that run are those of
-- List (T Int), T Int, List (String, T Int), (String, T Int), String and
-- Int, one function each, so the recursion closes over them.

data T : Type -> Type where
  Leaf : nm -> T nm
  Node : List (String, T nm) -> T nm

covering
Show nm => Show (T nm) where
  show (Leaf x) = show x
  show (Node xs) = "Node " ++ show xs

main : IO ()
main = printLn [Node [("a", Leaf 1), ("b", Node [("c", Leaf 2)])], Leaf (the Int 3)]
