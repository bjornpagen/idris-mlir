module Main

import Prelude
import Linear.Notation
import Linear.List

-- A recursion a million levels deep whose result is a linear list, which
-- each level hands to a function after the level under it returns: the
-- frame of each level waits for a value no other value may share, and
-- holds it as it would any other.

bumpHead : LList (!* Int) -@ LList (!* Int)
bumpHead [] = [MkBang 1]
bumpHead (MkBang x :: xs) = MkBang (x + 1) :: xs

tally : Int -> LList (!* Int)
tally 0 = []
tally n = bumpHead (tally (n - 1))

sumL : Int -> LList (!* Int) -@ !* Int
sumL acc [] = MkBang acc
sumL acc (MkBang x :: xs) = sumL (acc + x) xs

readInt : IO Int
readInt = go 0
  where
    go : Int -> IO Int
    go acc = do
      c <- getChar
      if isDigit c then go (acc * 10 + cast (ord c - 48)) else pure acc

main : IO ()
main = do
  n <- readInt
  let MkBang s = sumL 0 (tally n)
  printLn s
