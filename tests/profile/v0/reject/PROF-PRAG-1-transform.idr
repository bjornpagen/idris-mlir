-- expect: PROF-PRAG-1 line 10
module Main

slow : Int -> Int
slow x = prim__add_Int x 0

fast : Int -> Int
fast x = x

%transform "fast" slow = fast

main : Int
main = slow 3
