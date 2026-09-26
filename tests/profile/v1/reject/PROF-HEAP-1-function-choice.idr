-- expect: PROF-HEAP-1 line 19
module Main

import IdrisMLIR.IO

-- Which function is inside is chosen at runtime, and the choice outlives the
-- match: the value would need the heap.
data Op : Type where
  Inc : (Int -> Int) -> Op
  Dbl : (Int -> Int) -> Op

pick : Char -> Op
pick 'a' = Inc (prim__add_Int 1)
pick _ = Dbl (prim__mul_Int 2)

main : IO ()
main = do
  c <- getChar
  case pick c of
    Inc f => putStrLn (prim__cast_IntString (f 5))
    Dbl g => putStrLn (prim__cast_IntString (g 5))
