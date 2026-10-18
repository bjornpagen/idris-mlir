-- expect: escape hatch, line 6
module Main
import Prelude

coerce : Int -> Int
coerce x = prim__believe_me Int Int x -- not an unsupported (escape hatch) here

main : IO ()
main = printLn (coerce 5)
