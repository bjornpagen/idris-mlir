module Main

import IdrisMLIR.IO

applyTwice : (Int -> Int) -> Int -> Int
applyTwice f x = f (f x)

-- The number comes from stdin, so that the calls are not evaluated at
-- compile time (ELIM-G-12).
partial
main : IO ()
main = do
  c <- getChar
  let n = prim__sub_Int (prim__cast_CharInt c) 48
  putStrLn (prim__cast_IntString (applyTwice (prim__add_Int 1) n))
  putStrLn (prim__cast_IntString (applyTwice (prim__mul_Int 2) n))
