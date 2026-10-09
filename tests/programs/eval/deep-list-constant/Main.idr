module Main

-- A list of a hundred thousand numbers, computed at compile time into one
-- constant, which the compiler holds, writes and reads back flat: no step
-- of it takes a frame per element of the 8 MiB stack the compilation runs
-- on. The program walks it at run time with a weight it reads.

import Prelude

numbers : List Int
numbers = upTo 100000 []
  where
    upTo : Int -> List Int -> List Int
    upTo 0 acc = acc
    upTo n acc = upTo (n - 1) (n :: acc)

weighted : Int -> List Int -> Int -> Int
weighted k [] acc = acc
weighted k (x :: xs) acc = weighted k xs (acc + k * x)

main : IO ()
main = do
  c <- getChar
  printLn (weighted (cast (ord c - ord '0')) numbers 0)
