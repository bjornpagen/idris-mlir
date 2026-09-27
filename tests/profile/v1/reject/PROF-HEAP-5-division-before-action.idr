-- expect: PROF-HEAP-5 line 11
-- message: arity raising is blocked by a division
module Main

-- rule: DIAG-HEAP-1
-- The action `report d` is built, then "ready" is written, then the action
-- runs. Raising `report` would move its division after that output.

import IdrisMLIR.IO

partial
report : Int -> IO ()
report d = let q = prim__div_Int 100 d in putStrLn (prim__cast_IntString q)

partial
main : IO ()
main = do
  c <- getChar
  let action = report (prim__cast_CharInt c)
  putStrLn "ready"
  action
