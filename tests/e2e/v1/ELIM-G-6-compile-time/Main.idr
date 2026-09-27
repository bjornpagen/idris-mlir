module Main

import Prelude

main : IO ()
main = putStrLn (prim__strAppend (prim__cast_IntString (prim__mul_Int 6 7)) (prim__cast_CharString 'x'))
