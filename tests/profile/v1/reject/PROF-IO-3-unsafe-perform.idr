-- expect: PROF-IO-3 line 6
module Main

import IdrisMLIR.IO

n : Int
n = unsafePerformIO (pure 5)

main : IO ()
main = putStrLn (prim__cast_IntString n)
