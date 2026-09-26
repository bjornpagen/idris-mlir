-- expect: PROF-PRIM-4 line 10
module Main

import IdrisMLIR.IO

pick : Char -> String
pick 'a' = "one"
pick _ = "three"

main : IO ()
main = do
  c <- getChar
  putStrLn (prim__cast_IntString (prim__strLength (pick c)))
