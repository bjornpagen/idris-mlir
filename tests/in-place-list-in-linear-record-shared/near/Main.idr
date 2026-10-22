module Main

import Prelude
import Linear.Notation
import Linear.List

-- The refused program with the box it reads after the call built again,
-- so bumpBox is passed a box exclusive with its list, and rebuilds both
-- in place.

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
  let n = cast (ord c - ord '0')
  let MkBang bumped = totalOf (bumpBox (MkBox (MkBang 1) (build n [])))
  let MkBang plain = totalOf (MkBox (MkBang 1) (build n []))
  printLn (bumped, plain)
