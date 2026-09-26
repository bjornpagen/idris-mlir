-- stdout: 45\n
module Main

import IdrisMLIR.IO

twice : (a -> a) -> a -> a
twice f x = f (f x)

main : IO ()
main = putStrLn (prim__cast_IntString (twice (\x => prim__mul_Int x 3) 5))
