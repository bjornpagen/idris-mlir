module Prog

-- Division by zero: the divisor's guard fails, and the crash names the
-- cause and the definition whose division failed, loaded from its TTC,
-- which keeps no location inside a term.
export partial
quotient : Int -> Int -> Int
quotient x y = prim__div_Int x y
