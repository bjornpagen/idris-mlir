-- exit: 0
-- stdout: 2\n
module Main

-- rule: PROF-HEAP-1, OPT-SAFE-1
-- Was PROF-HEAP-5-division-run-at-once; renamed because PROF-HEAP-5 is
-- withdrawn with arity raising (docs/cutover.md A1, 4.2). `report` divides
-- by a runtime value and its action runs as soon as it is built; no closure
-- of it survives to runtime.

import Prelude

partial
report : Int -> IO ()
report d = let q = prim__div_Int 100 d in putStrLn (prim__cast_IntString q)

partial
main : IO ()
main = report 50
