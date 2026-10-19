module Main

-- `count` is called with a counter read at runtime and an accumulator that
-- is a constant, and grows by 3 at every call: specializing on it would
-- clone `count` forever, once per value, since the counter never becomes
-- known. `count` never branches on it, so it is generalized:
-- one clone, whose own call passes it as a runtime value (mlir.expect:
-- specialized-once); the program compiles, and the result is what the
-- source says.

import Prelude

count : Int -> Int -> Int
count 0 acc = acc
count k acc = count (k - 1) (acc + 3)

main : IO ()
main = do
  c <- getChar
  let n = the Int (cast (ord c) - 48)
  printLn (count (n * 1000) 0)
