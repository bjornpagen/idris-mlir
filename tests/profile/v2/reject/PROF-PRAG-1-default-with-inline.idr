-- expect: PROF-PRAG-1 line 7
module Main

-- rule: PROF-PRAG-1
%default total

%inline
one : Int
one = 1

main : Int
main = one
