module Main

import Prelude

main : IO ()
main = do
  putStrLn "hello"
  putStrLn (prim__strAppend "n = " (prim__cast_IntString 42))
