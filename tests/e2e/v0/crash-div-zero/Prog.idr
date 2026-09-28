module Prog

-- The quotient is unused; the division must still crash.
partial
divide : Int -> Int -> Int
divide a b = let q = prim__div_Int a b in 3

partial
main : Int
main = divide 10 0
