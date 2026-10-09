-- expect: uniqueness, line 25
-- message: which rebuilds it in place
module Main

import Prelude
import Linear.Notation
import Linear.List

-- With the in-place promise, a function that rebuilds its linear list in
-- the list's own cells must be passed the list exclusive. Here the list is
-- read again after the call, so the call passes it shared, and the promise
-- refuses the call.

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
  let MkBang plain = sumL 0 xs
  printLn (bumped, plain)
