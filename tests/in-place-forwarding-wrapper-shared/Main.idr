-- expect: uniqueness, line 34
-- message: wrapW
module Main

import Prelude
import Linear.Notation
import Linear.List

-- wrapW only forwards its list to bump, which rebuilds it, so the
-- requirement that the list be exclusive moves into wrapW's parameter, and
-- from there to wrapW's callers: the program's call, which reads the list
-- again after it, passes it shared and is refused there, where the
-- program can be changed, not inside wrapW. near/ builds a second list to
-- read.

build : Int -> LList (!* Int) -@ LList (!* Int)
build n acc = if n <= 0 then acc else build (n - 1) (MkBang n :: acc)

bump : LList (!* Int) -@ LList (!* Int)
bump [] = []
bump (MkBang x :: xs) = MkBang (x + 1) :: bump xs

wrapW : LList (!* Int) -> LList (!* Int)
wrapW xs = bump xs

sumL : Int -> LList (!* Int) -@ !* Int
sumL acc [] = MkBang acc
sumL acc (MkBang x :: xs) = sumL (acc + x) xs

main : IO ()
main = do
  c <- getChar
  let xs = build (cast (ord c - ord '0')) []
  let MkBang bumped = sumL 0 (wrapW xs)
  let MkBang plain = sumL 0 xs
  printLn (bumped, plain)
