-- stdout: 12\n
module Main

import Prelude

apply : (Int -> Int) -> Int -> Int
apply f x = f x

add : Int -> Int -> Int
add a b = prim__add_Int a b

main : IO ()
main = putStrLn (prim__cast_IntString (apply (add 5) 7))
