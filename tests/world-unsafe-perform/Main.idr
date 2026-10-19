-- expect: world, line 6
module Main

import Prelude

n : Int
n = unsafePerformIO (pure 5)

main : IO ()
main = putStrLn (prim__cast_IntString n)
