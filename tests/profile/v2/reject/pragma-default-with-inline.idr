-- expect: pragma, line 6
module Main

%default total

%inline
one : Int
one = 1

main : Int
main = one
