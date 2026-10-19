module Prog

-- NaN, of a division Idris does not hold covering, cast to an Int: the
-- value's guard fails, and the crash names the cause and the definition
-- whose cast failed, loaded from its TTC, which keeps no inner location.
export partial
nearest : Double -> Double -> Int
nearest x y = prim__cast_DoubleInt (prim__div_Double x y)
