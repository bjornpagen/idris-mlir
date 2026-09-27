module Main

import IdrisMLIR.IO

-- A recursive function passed a function: the whistle stops unfolding at
-- the recursive call, and the loop is specialized on the closure.
iter : (Int -> Int) -> Int -> Int -> Int
iter f 0 x = x
iter f n x = iter f (prim__sub_Int n 1) (f x)

-- The number comes from stdin, so that the calls are not evaluated at
-- compile time (ELIM-G-19).
partial
main : IO ()
main = do
  c <- getChar
  let n = prim__sub_Int (prim__cast_CharInt c) 48
  putStrLn (prim__cast_IntString (iter (prim__add_Int 1) n n))
  putStrLn (prim__cast_IntString (iter (prim__mul_Int 2) n 1))
