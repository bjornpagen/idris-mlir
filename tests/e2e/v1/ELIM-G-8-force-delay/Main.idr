module Main

import Prelude

choose : Int -> Lazy Int -> Lazy Int -> Int
choose 0 a b = a
choose _ a b = b

main : IO ()
main = do
  c <- getChar
  putStrLn (prim__cast_IntString (choose (prim__cast_CharInt c) 1 2))
