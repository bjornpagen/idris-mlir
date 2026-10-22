module Main

import Prelude
import Linear.Notation
import Linear.List

-- The refused program with the list it reads after the call built again,
-- so bumpIf is passed its list exclusive on either branch.

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
  let n = cast (ord c - ord '0')
  let MkBang bumped = sumL 0 (bumpIf (c > '4') (build n []))
  let MkBang plain = sumL 0 (build n [])
  printLn (bumped, plain)
