module Main

import Prelude
import Linear.Notation
import Linear.List

-- A total read of the list whose result nothing uses, before the list is
-- rebuilt. The read is evaluated, as every argument and binding is, and
-- it ends before the rebuild, keeping nothing of the list, so bump is
-- passed the list exclusive and rebuilds it in place. Whether the unused
-- read is later deleted (it may be: it is total) changes neither the
-- verdict nor the output.

build : Int -> LList (!* Int) -@ LList (!* Int)
build n acc = if n <= 0 then acc else build (n - 1) (MkBang n :: acc)

bump : LList (!* Int) -@ LList (!* Int)
bump [] = []
bump (MkBang x :: xs) = MkBang (x + 1) :: bump xs

sumL : Int -> LList (!* Int) -@ !* Int
sumL acc [] = MkBang acc
sumL acc (MkBang x :: xs) = sumL (acc + x) xs

total
lenT : LList (!* Int) -> Nat
lenT [] = Z
lenT (_ :: ys) = S (lenT ys)

main : IO ()
main = do
  c <- getChar
  let xs = build (cast (ord c - ord '0')) []
  let unused = lenT xs
  let MkBang bumped = sumL 0 (bump xs)
  printLn bumped
