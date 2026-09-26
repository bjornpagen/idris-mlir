-- expect: PROF-PRAG-1 line 4
module Main

%inline
one : Int
one = 1

main : Int
main = one
