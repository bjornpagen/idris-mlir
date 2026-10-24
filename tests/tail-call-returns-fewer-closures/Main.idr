module Main

-- pick gives a closure of its own, or the one doubled gives by a tail
-- call; doubled gives only its own, which runs the closure pick gave it
-- and doubles what it returns. So the call of doubled in pick returns
-- fewer closures than pick returns, and it is still pick's last act.
-- Each calls the other, and main calls each; the divisor comes from the
-- input, so pick may crash.

import Prelude

readInt : IO Int
readInt = go 0
  where
    go : Int -> IO Int
    go acc = do
      c <- getChar
      if isDigit c then go (acc * 10 + cast (ord c - 48)) else pure acc

mutual
  pick : Int -> Int -> (Int -> Int)
  pick 0 k = let d = div 100 k in \x => x + d
  pick n k = doubled (n - 1) k

  doubled : Int -> Int -> (Int -> Int)
  doubled n k = let h = pick n k in \x => h x * 2

main : IO ()
main = do
  n <- readInt
  k <- readInt
  let p = pick n k
  let q = doubled n k
  printLn (p 1)
  printLn (p 2)
  printLn (q 1)
