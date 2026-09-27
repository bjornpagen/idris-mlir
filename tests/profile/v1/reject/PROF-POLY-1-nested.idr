-- expect: PROF-POLY-1 line 8
module Main

-- rule: ELIM-MONO-3

import Prelude

depth : Int -> a -> Int
depth 0 _ = 0
depth n x = prim__add_Int 1 (depth (prim__sub_Int n 1) (MkPair x x))

main : IO ()
main = putStrLn (prim__cast_IntString (depth 3 'c'))
