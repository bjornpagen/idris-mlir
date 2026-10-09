module Prog

-- NaN, of a division Idris does not hold covering, cast to an Int: the
-- value's guard fails, and the crash names the cause and the definition
-- whose cast failed, loaded from its TTC, which keeps no inner location.
partial
nearest : Double -> Int
nearest x = prim__cast_DoubleInt (prim__div_Double x x)

export partial
result : Int
result = nearest 0.0
