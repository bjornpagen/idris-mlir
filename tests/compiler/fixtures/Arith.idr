module Arith

-- No Prelude: literals default to Int, arithmetic uses Idris primitives.

fib : Int -> Int
fib 0 = 0
fib 1 = 1
fib n = prim__add_Int (fib (prim__sub_Int n 1)) (fib (prim__sub_Int n 2))

-- The witness is quantity 0: recorded in the IR, absent from the MLIR.
keep : (0 witness : Int) -> Int -> Int
keep witness value = value

-- Argument order matters: diff 55 3 is 52, diff 3 55 would be -52.
diff : Int -> Int -> Int
diff a b = prim__sub_Int a b

-- Unsigned comparison: 200 < 100 is false for Bits8 (it would be true as Int8).
below : Bits8 -> Bits8 -> Int
below x y = prim__lt_Bits8 x y

-- Widening Bits8 zero-extends: 200 stays 200 rather than becoming -56.
widen : Bits8 -> Int
widen x = prim__cast_Bits8Int x

-- 52, plus 0 from `below`, plus 100 if widening wrongly sign-extended.
main : Int
main = prim__add_Int (prim__add_Int (keep 99 (diff (fib 10) 3))
                                    (below (prim__cast_IntBits8 200) (prim__cast_IntBits8 100)))
                     (prim__mul_Int 100 (prim__lt_Int (widen (prim__cast_IntBits8 200)) 0))
