-- expect: PROF-TYPE-4 line 9
module Main

import IdrisMLIR.IO

count : Integer -> Int
count _ = 3

main : IO ()
main = putStrLn (prim__cast_IntString (count 5))
