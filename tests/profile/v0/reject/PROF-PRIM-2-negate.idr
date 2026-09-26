-- expect: PROF-PRIM-2 line 5
module Main

neg : Int -> Int
neg x = prim__negate_Int x

main : Int
main = neg 5
