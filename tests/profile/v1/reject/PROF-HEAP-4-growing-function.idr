-- expect: PROF-HEAP-4 line 7
-- message: Main.iter passes itself a function, IO action, Lazy value or other static value that grows
module Main

import Prelude

iter : (Int -> Int) -> Int -> Int -> Int
iter f 0 x = f x
iter f n x = iter (\y => f (f y)) (prim__sub_Int n 1) x

main : IO ()
main = do
  c <- getChar
  putStrLn (prim__cast_IntString (iter (prim__add_Int 1) (prim__cast_CharInt c) 0))
