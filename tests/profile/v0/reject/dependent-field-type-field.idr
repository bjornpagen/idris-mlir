-- expect: dependent field, line 5
module Main

data Box : Type where
  MkBox : Type -> Box

size : Box -> Int
size (MkBox _) = 1

main : Int
main = size (MkBox Int)
