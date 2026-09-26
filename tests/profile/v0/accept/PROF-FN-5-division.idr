-- exit: 3
module Main

-- rule: FE-TOT-1
-- Division is partial in Idris; a function that divides is declared partial
-- and is accepted, because its own patterns cover every case.
partial
third : Int -> Int
third x = prim__div_Int x 3

partial
main : Int
main = third 10
