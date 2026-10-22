module Main

import Prelude
import Linear.Notation
import Linear.List

-- A list built after the match that took the parameter apart has
-- rejoined: the empty case reaches the construction with no cell, so the
-- construction rebuilds nothing and headList makes no promise. A caller
-- may pass it a list it reads again afterwards, and is not refused: the
-- list it reads keeps every value.

build : Int -> LList (!* Int) -@ LList (!* Int)
build n acc = if n <= 0 then acc else build (n - 1) (MkBang n :: acc)

sumL : Int -> LList (!* Int) -@ !* Int
sumL acc [] = MkBang acc
sumL acc (MkBang x :: xs) = sumL (acc + x) xs

headList : LList (!* Int) -@ LList (!* Int)
headList xs =
  let MkBang h = (case xs of
                    [] => MkBang 0
                    (MkBang x :: ys) => let MkBang _ = sumL 0 ys in MkBang x)
  in [MkBang h]

main : IO ()
main = do
  c <- getChar
  let xs = build (cast (ord c - ord '0')) []
  let MkBang first = sumL 0 (headList xs)
  let MkBang plain = sumL 0 xs
  printLn (first, plain)
