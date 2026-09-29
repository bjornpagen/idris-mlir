-- expect: runtime closure, line 17
module Main

import Prelude

-- Which function is inside is chosen by a recursion on a runtime value, and
-- each level builds a larger function from the one below: no finite choice
-- of static values stands for it, so it would need the heap. (A choice among
-- a fixed set of functions needs nothing: it is a tag.)
data Op : Type where
  Inc : (Int -> Int) -> Op
  Dbl : (Int -> Int) -> Op

pick : Int -> Op
pick 0 = Inc (prim__add_Int 1)
pick n =
  case pick (prim__sub_Int n 1) of
    Inc f => Dbl (\x => f (f x))
    Dbl g => Inc g

main : IO ()
main = do
  c <- getChar
  case pick (prim__cast_CharInt c) of
    Inc f => putStrLn (prim__cast_IntString (f 5))
    Dbl g => putStrLn (prim__cast_IntString (g 5))
