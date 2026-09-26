-- expect: PROF-FN-5 line 4
module Main

partial
pick : Int -> Int
pick 0 = 1

partial
main : Int
main = pick 0
