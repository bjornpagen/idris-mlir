module Main

import Prelude

main : IO ()
main = do
  c <- getChar
  putStrLn (prim__strAppend "got " (prim__strCons c (prim__strAppend " = " (prim__cast_IntString (prim__cast_CharInt c)))))
