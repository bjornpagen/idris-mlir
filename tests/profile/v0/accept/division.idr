-- stdout: 3\n
module Main
import Prelude

-- Division is partial in Idris; a function that divides is declared partial
-- and is accepted, because its own patterns cover every case.
partial
third : Int -> Int
third x = prim__div_Int x 3

partial
main : IO ()
main = printLn (third 10)
