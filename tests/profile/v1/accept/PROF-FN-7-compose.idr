-- stdout: 41\n
module Main

import Prelude

compose : (b -> c) -> (a -> b) -> a -> c
compose g f x = g (f x)

main : IO ()
main = putStrLn (prim__cast_IntString (compose (prim__add_Int 1) (prim__mul_Int 2) 20))
