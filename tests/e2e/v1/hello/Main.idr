module Main

import Prelude

-- rule: SEM-IO-2, LOW-STR-1, IDR-STR-1, IDR-IO-1, LOW-IO-2, LOW-IO-3, IDR-TY-4, IDR-TY-5
main : IO ()
main = do
  putStrLn "hello"
  putStrLn (prim__strAppend "n = " (prim__cast_IntString 42))
