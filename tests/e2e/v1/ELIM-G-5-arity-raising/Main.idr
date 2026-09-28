module Main

import Prelude

-- countdown returns an action. ELIM-G-5 (arity raising) is withdrawn at the
-- cutover (docs/cutover.md A1): inlining, apply of a known closure
-- (ELIM-G-1) and defunctionalization (ELIM-CLOS-1) remove the action's
-- closures instead, and the loop takes the world (IDR-WORLD-1). The count
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
