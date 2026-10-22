module Main

import Prelude
import Linear.Notation
import Linear.List

-- A rebuild that builds back exactly what it took apart: the cell is
-- the result, as it was, so nothing is written and nothing is built.

build : Int -> LList (!* Int) -@ LList (!* Int)
build n acc = if n <= 0 then acc else build (n - 1) (MkBang n :: acc)

sumL : Int -> LList (!* Int) -@ !* Int
sumL acc [] = MkBang acc
sumL acc (MkBang x :: xs) = sumL (acc + x) xs

same : LList (!* Int) -@ LList (!* Int)
same [] = []
same (x :: xs) = x :: xs

main : IO ()
main = do
  c <- getChar
  let MkBang s = sumL 0 (same (build (cast (ord c - ord '0')) []))
  printLn s
