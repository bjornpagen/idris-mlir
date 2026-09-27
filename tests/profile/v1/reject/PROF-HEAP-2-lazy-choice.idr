-- expect: PROF-HEAP-2 line 10
module Main

import IdrisMLIR.IO

data Later : Type where
  Soon : Lazy Int -> Later
  Never : Lazy Int -> Later

pick : Char -> Later
pick 'a' = Soon 1
pick _ = Never 2

main : IO ()
main = do
  c <- getChar
  case pick c of
    Soon x => putStrLn (prim__cast_IntString x)
    Never y => putStrLn (prim__cast_IntString y)
