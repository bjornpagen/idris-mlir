-- expect: uniqueness, line 27
-- message: reverse
module Main

import Prelude
import Linear.Notation
import Linear.List

-- The library's reverse rebuilds its list in place through reverseOnto, so
-- its parameter carries the promise, and the obligation passes back
-- through it to the call the program wrote: here the list is read again
-- after it is reversed, so it is passed shared, and the refusal is at the
-- program's own call, not inside the library. near/ builds a second list
-- to read.

build : Int -> LList (!* Int) -@ LList (!* Int)
build n acc = if n <= 0 then acc else build (n - 1) (MkBang n :: acc)

sumL : Int -> LList (!* Int) -@ !* Int
sumL acc [] = MkBang acc
sumL acc (MkBang x :: xs) = sumL (acc + x) xs

main : IO ()
main = do
  c <- getChar
  let xs = build (cast (ord c - ord '0')) []
  let MkBang reversed = sumL 0 (reverse xs)
  let MkBang plain = sumL 0 xs
  printLn (reversed, plain)
