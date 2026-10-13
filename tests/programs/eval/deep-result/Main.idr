module Main

import Prelude

-- `build 20000` stays a call: a closed call runs at run time. The
-- walk reads the list at run time. A reading quadratic in the depth would
-- not finish within the test's time limit.
build : Int -> List Int
build 0 = []
build n = n :: build (n - 1)

walk : Int -> Int -> List Int -> (Int, Int)
walk count acc [] = (count, acc)
walk count acc (x :: xs) = walk (count + 1) (acc + x) xs

main : IO ()
main = do
  c <- getChar
  let (count, sum) = walk 0 0 (if c == 'a' then [] else build 20000)
  printLn count
  printLn sum
