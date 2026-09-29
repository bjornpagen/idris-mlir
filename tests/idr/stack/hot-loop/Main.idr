module Main

-- Every iteration of `loop` builds two lists and hands them to `walk`,
-- which only reads them. `walk` takes its lists in turn, so neither of its
-- parameters is the same or smaller in its recursive call, and no
-- specialization knows their shapes: the cells stay to runtime. idr-stack
-- keeps them in `loop`'s frame, so the loop allocates nothing on the heap,
-- and every count still balances.

import Prelude

data L = Nil | Cons Int L

walk : L -> L -> Int
walk Nil ys = 0
walk (Cons x xs) ys = x + walk ys xs

partial
loop : Int -> Int -> Int
loop 0 acc = acc
loop n acc = loop (n - 1) (acc + walk (Cons n (Cons 1 Nil)) (Cons (mod n 7) Nil))

-- Digits by putChar, so that printing builds no string.
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
