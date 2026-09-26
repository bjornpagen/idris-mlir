-- expect: PROF-HEAP-4 line 7
-- message: Main.iter passes itself a function, IO action or Lazy value that grows
module Main

import IdrisMLIR.IO

iter : (Int -> Int) -> Int -> Int -> Int
iter f 0 x = f x
iter f n x = iter (\y => f (f y)) (prim__sub_Int n 1) x

main : IO ()
main = putStrLn (prim__cast_IntString (iter (prim__add_Int 1) 3 0))
