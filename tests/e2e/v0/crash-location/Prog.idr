module Prog

-- rule: LOW-CRASH-1
partial
f : Int -> Int
f x = prim__div_Int 10 x

partial
main : Int
main = f 0
