module Main

import Prelude

-- (\x => x * 3) 7 becomes a let; no lambda survives.
main : IO ()
main = putStrLn (prim__cast_IntString ((\x => prim__mul_Int x 3) 7))
