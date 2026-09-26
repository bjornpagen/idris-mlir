module Prog

public export
data Parity = Even | Odd

mutual
  public export
  isEven : Int -> Parity
  isEven 0 = Even
  isEven n = isOdd (prim__sub_Int n 1)

  public export
  isOdd : Int -> Parity
  isOdd 0 = Odd
  isOdd n = isEven (prim__sub_Int n 1)

public export
toInt : Parity -> Int
toInt Odd = 0
toInt Even = 1

public export
main : Int
main = prim__add_Int (prim__mul_Int 10 (toInt (isEven 1000))) (toInt (isOdd 7))
