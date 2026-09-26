-- expect: PROF-HEAP-3 line 13
-- message: a string is built at runtime here and is not written directly by putStr
module Main

import IdrisMLIR.IO

data Box : Type where
  MkBox : String -> Box

unbox : Box -> String
unbox (MkBox s) = s

main : IO ()
main = do
  c <- getChar
  putStrLn (unbox (MkBox (prim__strCons c "!")))
