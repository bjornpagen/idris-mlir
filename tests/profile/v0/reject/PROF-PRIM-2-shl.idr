-- expect: PROF-PRIM-2 line 5
module Main

shift : Int -> Int
shift x = prim__shl_Int x 3

main : Int
main = shift 1
