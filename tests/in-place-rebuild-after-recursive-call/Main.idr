module Main

import Prelude
import Linear.Notation
import Linear.List

-- A rebuild after a recursive call that is not a tail call: the cell
-- weave takes apart is rebuilt only once the call under it returns, so
-- the promise holds across that call, whose depth the frame stacks keep
-- rather than the native stack. weave [1..n] puts each head before the
-- reversal of what the rest weaves, so the order shows every level ran.

build : Int -> LList (!* Int) -@ LList (!* Int)
build n acc = if n <= 0 then acc else build (n - 1) (MkBang n :: acc)

digits : Int -> LList (!* Int) -@ !* Int
digits acc [] = MkBang acc
digits acc (MkBang x :: xs) = digits (acc * 10 + x) xs

weave : LList (!* Int) -@ LList (!* Int)
weave [] = []
weave (x :: xs) = x :: reverse (weave xs)

main : IO ()
main = do
  c <- getChar
  let MkBang woven = digits 0 (weave (build (cast (ord c - ord '0')) []))
  printLn woven
