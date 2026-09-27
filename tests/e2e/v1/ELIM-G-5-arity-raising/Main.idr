module Main

import IdrisMLIR.IO

-- countdown returns an action; raised, it takes the world and loops. The
-- count comes from stdin, so the loop is not unrolled (ELIM-G-19).
countdown : Int -> IO ()
countdown 0 = putStrLn "liftoff"
countdown n = do
  putStrLn (prim__cast_IntString n)
  countdown (prim__sub_Int n 1)

partial
main : IO ()
main = do
  c <- getChar
  countdown (prim__sub_Int (prim__cast_CharInt c) 48)
