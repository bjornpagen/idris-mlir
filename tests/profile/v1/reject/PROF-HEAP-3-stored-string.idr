-- expect: PROF-HEAP-3 line 12
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
