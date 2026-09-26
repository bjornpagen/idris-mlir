-- exit: 3
module Main

data Never : Type where

data T : Type where
  A : Int -> T
  B : Never -> T

get : T -> Int
get (A n) = n
get (B _) = 0

main : Int
main = get (A 3)
