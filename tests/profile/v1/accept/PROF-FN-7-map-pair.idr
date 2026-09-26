-- stdout: 3 8\n
module Main

import IdrisMLIR.IO

mapPair : (a -> b) -> Pair a a -> Pair b b
mapPair f (MkPair x y) = MkPair (f x) (f y)

main : IO ()
main = case mapPair (prim__add_Int 1) (MkPair 2 7) of
  MkPair a b => putStrLn (prim__strAppend (prim__cast_IntString a)
                            (prim__strAppend " " (prim__cast_IntString b)))
