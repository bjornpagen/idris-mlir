-- expect: PROF-PRIM-2 line 5
module Main

widen : Int -> Int
widen x = prim__cast_IntegerInt (prim__cast_IntInteger x)

main : Int
main = widen 5
