module Main

-- Functions called with literal arguments beside a runtime one, which
-- call-pattern specialization may clone on the literals: `ack` with m = 3
-- and 2 and n read at run time, `countUp` from the literal 1000, and
-- `count`, an IO loop from the literal 3. Whatever is cloned, each call
-- computes what the source says.

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
