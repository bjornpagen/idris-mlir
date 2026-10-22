-- expect: library, line 7
-- message: PrimIO.unsafePerformIO
module Main

import Prelude

n : Int
n = unsafePerformIO (pure 5)

main : IO ()
main = putStrLn (prim__cast_IntString n)
