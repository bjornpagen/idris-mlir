-- expect: uniqueness, line 39
-- message: bumpBox
module Main

import Prelude
import Linear.Notation
import Linear.List

-- A linear list bound at quantity 1 inside a linear record is promised a
-- rebuild in place as a parameter is: bumpBox takes the box apart and
-- rebuilds the list it holds, so the obligation reaches the box, and a
-- caller that reads the box again after the call passes it shared and is
-- refused. near/ builds a second box to read.

build : Int -> LList (!* Int) -@ LList (!* Int)
build n acc = if n <= 0 then acc else build (n - 1) (MkBang n :: acc)

bump : LList (!* Int) -@ LList (!* Int)
bump [] = []
bump (MkBang x :: xs) = MkBang (x + 1) :: bump xs

sumL : Int -> LList (!* Int) -@ !* Int
sumL acc [] = MkBang acc
sumL acc (MkBang x :: xs) = sumL (acc + x) xs

data Box : Type where
  MkBox : !* Int -@ LList (!* Int) -@ Box

bumpBox : Box -@ Box
bumpBox (MkBox (MkBang tag) xs) = MkBox (MkBang (tag + 1)) (bump xs)

totalOf : Box -@ !* Int
totalOf (MkBox (MkBang tag) xs) = let MkBang s = sumL 0 xs in MkBang (tag * 100 + s)

main : IO ()
main = do
  c <- getChar
  let box = MkBox (MkBang 1) (build (cast (ord c - ord '0')) [])
  let MkBang bumped = totalOf (bumpBox box)
  let MkBang plain = totalOf box
  printLn (bumped, plain)
