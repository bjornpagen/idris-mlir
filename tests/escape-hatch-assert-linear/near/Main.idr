module Main

import Prelude

-- The refused program without assert_linear: twice uses its argument
-- twice, so its argument is unrestricted, as its type now says.
twice : Int -> Int
twice x = (\y => y + y) x

main : IO ()
main = printLn (twice 21)
