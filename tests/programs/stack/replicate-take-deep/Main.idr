module Main

-- Data.List's replicate and take return a constructor around their own
-- result, so idr-trmc writes each cell to the destination it was given, in
-- a loop: ten million elements, where the harness gives a program a 1 MiB
-- stack. Their recursive call decrements a Nat it then gives up, which
-- borrow inference makes the callee's own, so that no drop sits between the
-- call and the constructor that idr-trmc moves the call past. The lists are
-- summed by a tail-recursive loop, so what is tested is replicate and take.

import Prelude
import Data.List

readInt : IO Int
readInt = go 0
  where
    go : Int -> IO Int
    go acc = do
      c <- getChar
      if isDigit c then go (acc * 10 + cast (ord c - 48)) else pure acc

sum : List Int -> Int -> Int
sum [] acc = acc
sum (x :: xs) acc = sum xs (acc + x)

main : IO ()
main = do
  n <- readInt
  let xs = replicate (cast n) 3
  printLn (sum xs 0)
  printLn (sum (take (cast (n `div` 2)) xs) 0)
