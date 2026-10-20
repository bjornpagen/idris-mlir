-- expect: type, line 19
-- message: Main.Box
module Main

-- Box's value depends on an Int, which an instance cannot take apart, so
-- unbox's parameter type depends on another argument. near/ indexes Box
-- by a Nat.

import Prelude

Box : Int -> Type
Box 0 = Int
Box _ = Char

unbox : (n : Int) -> Box n -> Int
unbox _ _ = 1

main : IO ()
main = putStrLn (prim__cast_IntString (unbox 0 5))
