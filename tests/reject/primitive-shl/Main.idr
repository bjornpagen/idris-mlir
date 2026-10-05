-- expect: primitive, line 5
module Main
import Prelude

shift : Integer -> Integer
shift x = prim__shl_Integer x 3

main : IO ()
main = printLn (shift 1)
