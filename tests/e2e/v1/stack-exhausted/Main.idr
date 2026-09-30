module Main

import Prelude

-- A non-tail recursion as deep as the number on stdin, a billion: each
-- call needs the result of the next before it can choose what to return,
-- so every frame stays. The program's reserved stack runs out: "read",
-- still in the output buffer, is written, the crash is named, and the
-- status is a crash's.
depth : Int -> Int
depth 0 = 0
depth n = let r = depth (n - 1) in if r > n then r - n else r + n

readInt : IO Int
readInt = go 0
  where
    go : Int -> IO Int
    go acc = do
      c <- getChar
      if isDigit c then go (acc * 10 + cast (ord c - 48)) else pure acc

main : IO ()
main = do
  putStrLn "started"
  n <- readInt
  putStrLn "read"
  printLn (depth n)
