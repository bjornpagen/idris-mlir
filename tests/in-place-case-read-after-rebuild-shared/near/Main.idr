module Main

import Prelude
import Linear.Notation
import Linear.List

-- The refused program with the branch's read of the list moved before the
-- call: every other use of the list, the read before the case among them,
-- ends before the call, so bump is passed the list exclusive and rebuilds
-- it in place.

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

finish : Int -> LList (!* Int) -@ Int
finish n ys = let MkBang s = sumL 0 ys in n * 100 + s

go : Int -> Int
go k =
  let xs = build k []
      n = countW xs
  in case xs of
       [] => n
       (_ :: _) => let m = countW xs
                       ys = bump xs
                   in finish (n + m) ys

main : IO ()
main = do
  c <- getChar
  printLn (go (cast (ord c - ord '0')))
