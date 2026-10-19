module Main

import Prelude

-- The refused program passing x on as it is, not paired: depth has the one
-- instance at Char, and counts down to 0.

depth : Int -> a -> Int
depth 0 _ = 0
depth n x = prim__add_Int 1 (depth (prim__sub_Int n 1) x)

main : IO ()
main = putStrLn (prim__cast_IntString (depth 3 'c'))
