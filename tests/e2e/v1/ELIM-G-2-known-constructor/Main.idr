module Main

import IdrisMLIR.IO

data Opt : Type where
  None : Opt
  Some : (Int -> Int) -> Opt

apply : Opt -> Int -> Int
apply None x = x
apply (Some f) x = f x

main : IO ()
main = putStrLn (prim__cast_IntString (apply (Some (prim__add_Int 10)) 5))
