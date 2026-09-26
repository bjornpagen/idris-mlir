-- exit: 1
module Main

mutual
  even : Int -> Int
  even 0 = 1
  even n = odd (prim__sub_Int n 1)

  odd : Int -> Int
  odd 0 = 0
  odd n = even (prim__sub_Int n 1)

main : Int
main = even 10
