-- expect: PROF-DATA-3 line 12
module Main

data A : Type
data B : Type

data A : Type where
  EndA : A
  ToB : B -> A

data B : Type where
  ToA : A -> B

isEnd : A -> Int
isEnd EndA = 1
isEnd (ToB _) = 0

main : Int
main = isEnd EndA
