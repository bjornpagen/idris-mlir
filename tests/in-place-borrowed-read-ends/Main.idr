module Main

import Prelude
import Linear.Notation
import Linear.List

-- A read of a linear list that ends before the list is rebuilt does not
-- share it: countW only reads the list it is lent, and keeps nothing of
-- it, so when bump takes the list the read is over and bump is passed it
-- exclusive, rebuilding it in place. A use counts against the promise only
-- if it may still hold the list at the rebuild.

build : Int -> LList (!* Int) -@ LList (!* Int)
build n acc = if n <= 0 then acc else build (n - 1) (MkBang n :: acc)

countW : LList (!* Int) -> Int
countW [] = 0
countW (_ :: xs) = 1 + countW xs

bump : LList (!* Int) -@ LList (!* Int)
bump [] = []
bump (MkBang x :: xs) = MkBang (x + 1) :: bump xs

sumL : Int -> LList (!* Int) -@ !* Int
sumL acc [] = MkBang acc
sumL acc (MkBang x :: xs) = sumL (acc + x) xs

main : IO ()
main = do
  c <- getChar
  let xs = build (cast (ord c - ord '0')) []
  let n = countW xs
  let MkBang bumped = sumL 0 (bump xs)
  printLn (n, bumped)
