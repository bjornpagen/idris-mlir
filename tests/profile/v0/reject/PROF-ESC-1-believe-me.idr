-- expect: PROF-ESC-1 line 5
module Main

coerce : Int -> Int
coerce x = prim__believe_me Int Int x

main : Int
main = coerce 5
