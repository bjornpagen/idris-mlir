module Main

import IdrisMLIR.IO

-- rule: SEM-IO-4, SEM-CRASH-1
partial
main : IO ()
main = do
  putStrLn "first"
  c <- getChar
  putStrLn (prim__cast_IntString (prim__div_Int 10 (prim__cast_CharInt c)))
