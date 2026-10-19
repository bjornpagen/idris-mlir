module Main

import Prelude

-- The refused program comparing the Double where it matched on a literal.
isHalf : Double -> Int
isHalf x = if x == 0.5 then 1 else 0

partial
main : IO ()
main = putStrLn (prim__cast_IntString (isHalf (prim__div_Double 1.0 2.0)))
