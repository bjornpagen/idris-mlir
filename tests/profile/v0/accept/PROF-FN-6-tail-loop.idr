-- exit: 32
module Main

-- rule: LOW-TAIL-1, SEM-RES-2
sumTo : Int -> Int -> Int
sumTo 0 acc = acc
sumTo n acc = sumTo (prim__sub_Int n 1) (prim__add_Int acc n)

main : Int
main = prim__and_Int (sumTo 1000000 0) 255
