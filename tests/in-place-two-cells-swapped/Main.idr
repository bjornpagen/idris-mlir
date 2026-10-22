module Main

import Prelude
import Linear.Notation
import Linear.List

-- Two cells taken apart and two built in one clause, their heads swapped:
-- both constructions are rebuilds of the cells taken apart, so each is in
-- one of them and no cell of the list is allocated or freed.

build : Int -> LList (!* Int) -@ LList (!* Int)
build n acc = if n <= 0 then acc else build (n - 1) (MkBang n :: acc)

digits : Int -> LList (!* Int) -@ !* Int
digits acc [] = MkBang acc
digits acc (MkBang x :: xs) = digits (acc * 10 + x) xs

swap : LList (!* Int) -@ LList (!* Int)
swap [] = []
swap [x] = [x]
swap (x :: y :: zs) = y :: x :: swap zs

main : IO ()
main = do
  c <- getChar
  let MkBang swapped = digits 0 (swap (build (cast (ord c - ord '0')) []))
  printLn swapped
