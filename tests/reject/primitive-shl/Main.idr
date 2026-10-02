-- expect: primitive, line 5
module Main
import Prelude

shift : Int -> Int
shift x = prim__shl_Int x 3

main : IO ()
main = printLn (shift 1)
