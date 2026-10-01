-- The linear data of libs/linear, whose constructors are typed with -@:
-- a list of unrestricted Ints built, reversed and summed in place, and its
-- length counted as a linear natural.
module Main

import Prelude
import Linear.List
import Linear.Nat
import Linear.Notation

build : Int -> LList (!* Int) -@ LList (!* Int)
build n acc = if n <= 0 then acc else build (n - 1) (MkBang n :: acc)

rev : LList a -@ LList a -@ LList a
rev [] acc = acc
rev (x :: xs) acc = rev xs (x :: acc)

sumL : Int -> LList (!* Int) -@ !* Int
sumL acc [] = MkBang acc
sumL acc (MkBang x :: xs) = sumL (acc * 3 + x) xs

len : LList (!* Int) -@ LNat
len [] = Zero
len (MkBang _ :: xs) = Succ (len xs)

toInt : Int -> LNat -@ !* Int
toInt acc Zero = MkBang acc
toInt acc (Succ n) = toInt (acc + 1) n

main : IO ()
main = do
  n <- pure 30
  let MkBang s = sumL 0 (rev (build n []) [])
  printLn s
  let MkBang l = toInt 0 (len (build n []))
  printLn l
