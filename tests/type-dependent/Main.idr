-- expect: type, line 13
module Main

import Prelude

Box : Int -> Type
Box 0 = Int
Box _ = Char

unbox : (n : Int) -> Box n -> Int
unbox _ _ = 1

main : IO ()
main = putStrLn (prim__cast_IntString (unbox 0 5))
