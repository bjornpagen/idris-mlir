module Main

-- The longest Collatz sequence starting below n: integer division in loops.

import Prelude
import IdrisMLIR.IO


steps : Int -> Int -> Int
steps 1 acc = acc
steps m acc = steps (if m `mod` 2 == 0 then m `div` 2 else 3 * m + 1) (acc + 1)

longest : Int -> Int -> Int -> Int -> Int
longest n i best at =
  if i >= n then at
  else let s = steps i 0 in
       if s > best then longest n (i + 1) s i else longest n (i + 1) best at

readInt : IO Int
readInt = go 0
  where
    go : Int -> IO Int
    go acc = do
      c <- getChar
      if isDigit c then go (acc * 10 + cast (ord c - 48)) else pure acc

main : IO ()
main = do
  n <- readInt
  printLn (longest n 1 0 1)
