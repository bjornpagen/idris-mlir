module Main

-- Every iteration of `loop` builds a list whose shape depends on the
-- counter, so no specialization can know it, and passes it to `sumL`,
-- which only reads it. idr-stack keeps its cells in `loop`'s frame: the
-- loop allocates nothing on the heap, and every count balances.

import Prelude

data L = Nil | Cons Int L

sumL : L -> Int
sumL Nil = 0
sumL (Cons x xs) = x + sumL xs

pick : Int -> Int -> L
pick n k = if mod n 3 == 0 then Cons n Nil else Cons n (Cons k Nil)

partial
loop : Int -> Int -> Int
loop 0 acc = acc
loop n acc = loop (n - 1) (acc + sumL (pick n (mod n 7)))

-- Digits by putChar, so that printing allocates no string either.
partial
digits : Int -> IO ()
digits n = do
  if n >= 10 then digits (div n 10) else pure ()
  putChar (chr (48 + cast (mod n 10)))

partial
main : IO ()
main = do
  c <- getChar
  digits (loop (cast (ord c) * 1000) 0)
  putChar '\n'
