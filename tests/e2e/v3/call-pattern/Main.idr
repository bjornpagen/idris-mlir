module Main

-- rule: ELIM-G-18, ELIM-G-5
-- Call-pattern specialization on literals: `ack` matches on `m`, and is
-- called with the literal 3, so it is specialized for m = 3, 2, 1 and 0,
-- with n a runtime value. `count`, an IO loop that matches on its
-- counter, is an action, and stays one loop.

import Prelude

ack : Int -> Int -> Int
ack 0 n = n + 1
ack m 0 = ack (m - 1) 1
ack m n = ack (m - 1) (ack m (n - 1))

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
  count 3
