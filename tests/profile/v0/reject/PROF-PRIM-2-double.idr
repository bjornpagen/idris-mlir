-- expect: PROF-PRIM-2 line 5
module Main

viaDouble : Int -> Int
viaDouble x = prim__cast_DoubleInt (prim__cast_IntDouble x)

main : Int
main = viaDouble 5
