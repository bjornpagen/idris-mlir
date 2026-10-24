-- expect: uniqueness, line 41
-- message: Main.bump
module Main

import Prelude
import Linear.Notation
import Linear.List

-- A case on a let-bound linear list whose branch passes the list to a
-- function that rebuilds it in its own cells. The list the branch passes
-- is the let's, entered into the case, so the call is passed it exclusive
-- only where every other use of it, before the case and in the branch, is
-- a read that ends before the call. Here the branch reads the list again
-- after the call, so the call passes it shared and is refused. near/ reads
-- it before the call.

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
       (_ :: _) => let ys = bump xs
                       m = countW xs
                   in finish (n + m) ys

main : IO ()
main = do
  c <- getChar
  printLn (go (cast (ord c - ord '0')))
