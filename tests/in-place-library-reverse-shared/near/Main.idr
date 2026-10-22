module Main

import Prelude
import Linear.Notation
import Linear.List

-- The refused program with the list it reads after the reverse built
-- again, so each list is used once and reverse is passed its list
-- exclusive.

build : Int -> LList (!* Int) -@ LList (!* Int)
build n acc = if n <= 0 then acc else build (n - 1) (MkBang n :: acc)

sumL : Int -> LList (!* Int) -@ !* Int
sumL acc [] = MkBang acc
sumL acc (MkBang x :: xs) = sumL (acc + x) xs

main : IO ()
main = do
  c <- getChar
  let n = cast (ord c - ord '0')
  let MkBang reversed = sumL 0 (reverse (build n []))
  let MkBang plain = sumL 0 (build n [])
  printLn (reversed, plain)
