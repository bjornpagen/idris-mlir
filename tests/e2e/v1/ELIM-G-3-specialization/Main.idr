module Main

import IdrisMLIR.IO

applyTwice : (Int -> Int) -> Int -> Int
applyTwice f x = f (f x)

main : IO ()
main = do
  putStrLn (prim__cast_IntString (applyTwice (prim__add_Int 1) 5))
  putStrLn (prim__cast_IntString (applyTwice (prim__mul_Int 2) 5))
