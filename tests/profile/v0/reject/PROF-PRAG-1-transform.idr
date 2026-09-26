-- expect: PROF-PRAG-1 line 11
module Main
-- rule: RW-DAY1-4

slow : Int -> Int
slow x = prim__add_Int x 0

fast : Int -> Int
fast x = x

%transform "fast" slow = fast

main : Int
main = slow 3
