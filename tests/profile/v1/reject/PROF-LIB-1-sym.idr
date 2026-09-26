-- expect: PROF-LIB-1 line 6
module Main

import IdrisMLIR.IO

main : IO ()
main = case sym (Refl {x = 'a'}) of
         Refl => putStrLn "x"
