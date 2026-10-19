module Main

import Prelude

-- A list built by recursion and summed: its cells are made and freed by
-- the runtime the program links.
build : Nat -> List Integer
build Z = []
build (S k) = cast (S k) :: build k

main : IO ()
main = printLn (sum (build 7))
