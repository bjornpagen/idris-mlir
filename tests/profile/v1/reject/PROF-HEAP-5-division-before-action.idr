-- expect: PROF-HEAP-5 line 6
module Main

import IdrisMLIR.IO

partial
report : Int -> IO ()
report d = let q = prim__div_Int 100 d in putStrLn (prim__cast_IntString q)

partial
main : IO ()
main = do
  c <- getChar
  report (prim__cast_CharInt c)
