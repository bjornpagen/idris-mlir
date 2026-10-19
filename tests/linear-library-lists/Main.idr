-- The linear data of libs/linear, whose constructors are typed with -@:
-- a list of unrestricted Ints built, reversed and summed in place, and its
-- length counted as a linear natural, n read: 0 is the empty list.
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
  let MkBang s = sumL 0 (rev (build n []) [])
  printLn s
  let MkBang l = toInt 0 (len (build n []))
  printLn l
