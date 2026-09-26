-- expect: PROF-DATA-2 line 5
module Main

data Big : Type where
  MkBig : Integer -> Big

size : Big -> Int
size (MkBig _) = 1

main : Int
main = size (MkBig 5)
