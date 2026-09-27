-- exit: 0
-- stdout: 2\n
module Main

-- rule: PROF-HEAP-5
-- `report` divides by a runtime value, but its action runs as soon as it is
-- built, with no effect in between, so raising it is not observable.

import Prelude

partial
report : Int -> IO ()
report d = let q = prim__div_Int 100 d in putStrLn (prim__cast_IntString q)

partial
main : IO ()
main = report 50
