module Main

-- isEven and isOdd call each other in tail position: neither calls itself,
-- so no loop is made of them, and the recursion runs in
-- constant stack only as guaranteed tail calls. Ten million calls, each a
-- jump.

import Prelude

readInt : IO Int
readInt = go 0
  where
    go : Int -> IO Int
    go acc = do
      c <- getChar
      if isDigit c then go (acc * 10 + cast (ord c - 48)) else pure acc

mutual
  isEven : Int -> Bool
  isEven 0 = True
  isEven n = isOdd (n - 1)

  isOdd : Int -> Bool
  isOdd 0 = False
  isOdd n = isEven (n - 1)

main : IO ()
main = do
  n <- readInt
  printLn (isEven n)
  printLn (isOdd (n + 1))
