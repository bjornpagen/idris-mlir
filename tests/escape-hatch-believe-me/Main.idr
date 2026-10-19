-- expect: escape hatch, line 7
-- message: prim__believe_me
module Main
import Prelude

coerce : Int -> Int
coerce x = prim__believe_me Int Int x

main : IO ()
main = printLn (coerce 5)
