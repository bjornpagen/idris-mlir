module Main

import Prelude

-- countdown returns an action. ELIM-G-5 (arity raising): idr-specialize
-- moves the apply that runs the action into a clone of countdown, where
-- it meets the closures the body built (ELIM-G-1), so no closure is left
-- and the loop takes the world (IDR-WORLD-1). The count
-- comes from stdin, and countdown recurses on an Int, so it is not
-- evaluated at compile time (SEM-EVAL-6).
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
