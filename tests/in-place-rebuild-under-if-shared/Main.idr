-- expect: uniqueness, line 30
-- message: bumpIf
module Main

import Prelude
import Linear.Notation
import Linear.List

-- A rebuild that sits under an `if` on the right-hand side is a rebuild
-- all the same: on either branch bumpIf builds a list from the cell it
-- took apart, so its parameter carries the promise whichever branch runs,
-- and a caller that reads the list again after the call passes it shared
-- and is refused. near/ builds a second list to read.

build : Int -> LList (!* Int) -@ LList (!* Int)
build n acc = if n <= 0 then acc else build (n - 1) (MkBang n :: acc)

bumpIf : Bool -> LList (!* Int) -@ LList (!* Int)
bumpIf b [] = []
bumpIf b (MkBang x :: xs) = if b then MkBang (x + 1) :: bumpIf b xs else MkBang x :: xs

sumL : Int -> LList (!* Int) -@ !* Int
sumL acc [] = MkBang acc
sumL acc (MkBang x :: xs) = sumL (acc + x) xs

main : IO ()
main = do
  c <- getChar
  let xs = build (cast (ord c - ord '0')) []
  let MkBang bumped = sumL 0 (bumpIf (c > '4') xs)
  let MkBang plain = sumL 0 xs
  printLn (bumped, plain)
