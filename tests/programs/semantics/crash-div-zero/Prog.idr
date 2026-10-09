module Prog

-- The quotient is unused; the division must still crash, before anything
-- is printed: a crash is an effect, kept in program order.
partial
divide : Int -> Int -> Int
divide a b = let q = prim__div_Int a b in 3

export partial
result : Int
result = divide 10 0
