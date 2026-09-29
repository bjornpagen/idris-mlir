-- expect: pragma, line 4
module Main

%inline
one : Int
one = 1

main : Int
main = one
