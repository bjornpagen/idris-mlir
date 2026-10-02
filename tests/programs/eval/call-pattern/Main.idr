module Main

-- Call-pattern specialization on a small counter: `ack` counts `m` down,
-- and is called with the literal 3, so it is specialized for m = 3, 2 and
-- 1, with n a runtime value; m = 0 folds where it is called. `count`, an IO
-- loop called with a literal, writes output, so its closed call is not
-- evaluated: it runs as a loop that takes the world. `countUp` counts down
-- from the literal 1000, too far to unroll: it stays one function.

import Prelude

ack : Int -> Int -> Int
ack 0 n = n + 1
ack m 0 = ack (m - 1) 1
ack m n = ack (m - 1) (ack m (n - 1))

countUp : Int -> Int -> Int
countUp 0 acc = acc
countUp k acc = countUp (k - 1) (acc + 1)

count : Int -> IO ()
count 0 = putStrLn "done"
count k = do
  printLn k
  count (k - 1)

main : IO ()
main = do
  c <- getChar
  let n = the Int (cast (ord c) - 48)
  printLn (ack 3 n)
  printLn (ack 2 n)
  printLn (countUp 1000 n)
  count 3
