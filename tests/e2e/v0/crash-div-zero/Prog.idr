module Prog

-- rule: SEM-INT-4, LOW-CRASH-1, OPT-SAFE-1, SEM-EVAL-4, IDR-EFF-1
-- The quotient is unused; the division must still crash.
partial
divide : Int -> Int -> Int
divide a b = let q = prim__div_Int a b in 3

partial
main : Int
main = divide 10 0
