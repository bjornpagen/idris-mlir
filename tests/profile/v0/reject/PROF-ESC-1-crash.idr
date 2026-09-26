-- expect: PROF-ESC-1 line 6
module Main

partial
stop : Int -> Int
stop x = prim__crash Int "no"

partial
main : Int
main = stop 5
