-- A constructor typed with -@ is the one with explicit linear binders:
-- `a -@ b` is `(1 _ : a) -> b`. The same list, written both ways, and a
-- parameterised one, compute the same sums, for the n read: 0 is the
-- empty list, and past 40 the sums wrap as Int arithmetic does.
module Main

import Prelude
import Linear.Notation

data Bound : Type where
  BNil : Bound
  BCons : (1 _ : Int) -> (1 _ : Bound) -> Bound

data Arrow : Type where
  ANil : Arrow
  ACons : Int -@ Arrow -@ Arrow

data Poly : Type -> Type where
  PNil : Poly a
  PCons : a -@ Poly a -@ Poly a

buildB : Int -> Bound -@ Bound
buildB n acc = if n <= 0 then acc else buildB (n - 1) (BCons n acc)

revB : Bound -@ Bound -@ Bound
revB BNil acc = acc
revB (BCons x xs) acc = revB xs (BCons x acc)

sumB : Int -> Bound -> Int
sumB acc BNil = acc
sumB acc (BCons x xs) = sumB (acc * 3 + x) xs

buildA : Int -> Arrow -@ Arrow
buildA n acc = if n <= 0 then acc else buildA (n - 1) (ACons n acc)

revA : Arrow -@ Arrow -@ Arrow
revA ANil acc = acc
revA (ACons x xs) acc = revA xs (ACons x acc)

sumA : Int -> Arrow -> Int
sumA acc ANil = acc
sumA acc (ACons x xs) = sumA (acc * 3 + x) xs

buildP : Int -> Poly Int -@ Poly Int
buildP n acc = if n <= 0 then acc else buildP (n - 1) (PCons n acc)

revP : Poly a -@ Poly a -@ Poly a
revP PNil acc = acc
revP (PCons x xs) acc = revP xs (PCons x acc)

sumP : Int -> Poly Int -> Int
sumP acc PNil = acc
sumP acc (PCons x xs) = sumP (acc * 3 + x) xs

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
  printLn (sumB 0 (revB (buildB n BNil) BNil))
  printLn (sumA 0 (revA (buildA n ANil) ANil))
  printLn (sumP 0 (revP (buildP n PNil) PNil))
