module Main

-- A Show implementation for a rose tree: its show calls the Prelude's show
-- of a list, which calls it back through the dictionary. The cycle holds
-- functions of the user and of the Prelude; it breaks at one that does not
-- break last (the registry's column), never at one of Builtin or PrimIO.

import Prelude

%default covering

data Rose = Node Int (List Rose)

covering
implementation Show Rose where
  show (Node n ts) = "Node " ++ show n ++ " " ++ show ts

build : Int -> Rose
build 0 = Node 0 []
build k = Node k [build (k - 1)]

main : IO ()
main = do
  s <- getLine
  putStrLn (show [build (cast s)])
