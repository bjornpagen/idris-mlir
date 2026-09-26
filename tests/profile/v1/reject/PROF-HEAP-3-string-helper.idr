-- expect: PROF-HEAP-3 line 8
module Main

import IdrisMLIR.IO

-- Output fusion (ELIM-G-7) rewrites putStr of a string expression, not the
-- result of a function that builds one: that string would need the heap.
show : Int -> String
show n = prim__cast_IntString n

main : IO ()
main = putStrLn (show 5)
