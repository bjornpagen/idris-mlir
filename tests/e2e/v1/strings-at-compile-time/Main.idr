module Main

import Prelude

-- rule: SEM-STR-1, ELIM-G-6
public export
greeting : String
greeting = prim__strAppend (prim__strCons 'h' "ello") (prim__strAppend ", " (prim__cast_CharString 'w'))

main : IO ()
main = do
  putStrLn greeting
  putStrLn (prim__cast_IntString (prim__strLength (prim__strAppend "hello" ", w")))
  putStrLn (prim__strReverse "abc")
