module Prog

-- Division by zero: the divisor's guard fails, and the crash names the
-- cause and the definition whose division failed, loaded from its TTC,
-- which keeps no location inside a term.
partial
quotient : Int -> Int
quotient x = prim__div_Int 10 x

export partial
result : Int
result = quotient 0
