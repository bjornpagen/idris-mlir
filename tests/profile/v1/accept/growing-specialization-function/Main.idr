module Main

import Prelude

-- Each level of the recursion builds a larger function from the one below,
-- so no finite choice of functions stands for the one `iter` applies at
-- the end: its closures are built on the heap, each holding the one below.
iter : (Int -> Int) -> Int -> Int -> Int
iter f 0 x = f x
iter f n x = iter (\y => f (f y)) (prim__sub_Int n 1) x

main : IO ()
main = do
  c <- getChar
  putStrLn (prim__cast_IntString (iter (prim__add_Int 1) (prim__cast_CharInt c) 0))
