module Prog

-- A crash reports the source location of the operation that failed.
partial
f : Int -> Int
f x = prim__div_Int 10 x

partial
main : Int
main = f 0
