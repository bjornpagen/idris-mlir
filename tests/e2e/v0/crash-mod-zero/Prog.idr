module Prog

partial
rem : Int -> Int -> Bits8
rem a b = prim__mod_Bits8 (prim__cast_IntBits8 a) (prim__cast_IntBits8 b)

partial
main : Int
main = prim__cast_Bits8Int (rem 10 256)
