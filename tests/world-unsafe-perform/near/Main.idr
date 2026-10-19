module Main

import Prelude

-- The refused program with the value pure, not performed.
n : Int
n = 5

main : IO ()
main = putStrLn (prim__cast_IntString n)
