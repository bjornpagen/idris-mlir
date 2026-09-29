-- expect: growing specialization, line 7
-- message: is built in or passed to @Main.iter, whose specialization stopped
module Main

import Prelude

iter : (Int -> Int) -> Int -> Int -> Int
iter f 0 x = f x
iter f n x = iter (\y => f (f y)) (prim__sub_Int n 1) x

main : IO ()
main = do
  c <- getChar
  putStrLn (prim__cast_IntString (iter (prim__add_Int 1) (prim__cast_CharInt c) 0))
