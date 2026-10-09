module Main
import Prelude

fib : Int -> Int
fib 0 = 0
fib 1 = 1
fib n = prim__add_Int (fib (prim__sub_Int n 1)) (fib (prim__sub_Int n 2))

main : IO ()
main = printLn (fib 10)
