module Main
import Prelude

-- The refused program without believe_me: an Int is already an Int.
coerce : Int -> Int
coerce x = x

main : IO ()
main = printLn (coerce 5)
