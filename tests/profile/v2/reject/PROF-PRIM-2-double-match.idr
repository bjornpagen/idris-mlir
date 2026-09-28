-- expect: PROF-PRIM-2 line 6
module Main

import Prelude

isHalf : Double -> Int
isHalf 0.5 = 1
isHalf _ = 0

main : IO ()
main = putStrLn (prim__cast_IntString (isHalf (prim__div_Double 1.0 2.0)))
