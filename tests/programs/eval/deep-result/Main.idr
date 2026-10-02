module Main

import Prelude

-- `build 20000` is a closed call, so it is evaluated: a list of 20,000
-- cells, a constant nested 20,000 deep. Reading it back from the
-- evaluation takes time linear in its size, so the whole compilation fits
-- well within its time limit; a reading quadratic in the depth would not.
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
