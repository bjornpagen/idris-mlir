-- exit: 0
-- stdout: ready\n0\n
module Main

-- rule: PROF-HEAP-1, OPT-SAFE-1, SEM-EVAL-2
-- Was the reject fixture PROF-HEAP-5-division-before-action, and is an
-- accept since the cutover (PROF-GEN-4): PROF-HEAP-5 and arity
-- raising are withdrawn. The action `report d` is built, then "ready" is
-- written, then the action runs; inlining and defunctionalization remove its
-- closure without moving the division, which runs where Idris runs it, as
-- Chez does. On empty stdin getChar returns character 255 (SEM-IO-7), so
-- the division is 100 div 255 = 0 and does not crash.

import Prelude

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
