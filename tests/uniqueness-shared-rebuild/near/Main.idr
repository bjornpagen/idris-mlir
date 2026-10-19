module Main

import Prelude
import Linear.Notation
import Linear.List

-- The refused program with the list it reads after the call built again,
-- so each list is used once and bump is passed its list exclusive.

build : Int -> LList (!* Int) -@ LList (!* Int)
build n acc = if n <= 0 then acc else build (n - 1) (MkBang n :: acc)

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
  let MkBang bumped = sumL 0 (bump xs)
  let MkBang plain = sumL 0 (build (cast (ord c - ord '0')) [])
  printLn (bumped, plain)
