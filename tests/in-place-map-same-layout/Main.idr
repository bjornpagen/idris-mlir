module Main

import Prelude
import Linear.Notation
import Linear.List

-- A map over a linear list whose element type it changes in name but not
-- in layout: each output cell is of the same family and the same size as
-- the input cell it is built from, so each is a rebuild of that cell.

build : Int -> LList (!* Int) -@ LList (!* Int)
build n acc = if n <= 0 then acc else build (n - 1) (MkBang n :: acc)

sumL : Int -> LList (!* Int) -@ !* Int
sumL acc [] = MkBang acc
sumL acc (MkBang x :: xs) = sumL (acc + x) xs

mapL : (a -@ b) -> LList a -@ LList b
mapL f [] = []
mapL f (x :: xs) = f x :: mapL f xs

triple : !* Int -@ !* Int
triple (MkBang x) = MkBang (x * 3)

main : IO ()
main = do
  c <- getChar
  let MkBang s = sumL 0 (mapL triple (build (cast (ord c - ord '0')) []))
  printLn s
