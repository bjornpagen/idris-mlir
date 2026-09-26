-- exit: 5
module Main

-- rule: PROF-TYPE-1, SEM-Q-1, ELIM-ERASE-1
-- A quantity-0 argument of a type that is not a runtime type.
data IsFive : Int -> Type where
  ItIs : IsFive 5

five : (x : Int) -> (0 _ : IsFive x) -> Int
five x _ = x

main : Int
main = five 5 ItIs
