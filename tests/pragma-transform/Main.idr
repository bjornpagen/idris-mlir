-- expect: pragma, line 11
module Main
import Prelude

slow : Int -> Int
slow x = prim__add_Int x 0

fast : Int -> Int
fast x = x

%transform "fast" slow = fast

main : IO ()
main = printLn (slow 3)
