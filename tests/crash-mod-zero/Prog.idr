module Prog

-- The remainder of two Bits8, each an Int cast modulo 256: a divisor of 256
-- is 0, and the remainder crashes. It crashes exactly when the divisor is
-- 0 as a Bits8, whether that is read at run time or written in a closed
-- call.
export partial
rem : Int -> Int -> Bits8
rem a b = prim__mod_Bits8 (prim__cast_IntBits8 a) (prim__cast_IntBits8 b)

export partial
result : Int
result = prim__cast_Bits8Int (rem 10 256)
