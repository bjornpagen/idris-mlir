module Main

-- A natural counted down to zero, a hundred million steps and one read at
-- runtime, so that the digit decides the parity.
-- Its only other state is a Bool, so once one test on entry has found the
-- natural small the loop runs on machine words: mlir.expect states that
-- some loop of parity holds no big at all.

import Prelude

parity : Nat -> Bool -> Bool
parity Z odd = odd
parity (S k) odd = parity k (not odd)

main : IO ()
main = do
  c <- getChar
  let d = the Int (cast (ord c) - 48)
  let n = the Nat (cast (d * 100000000 + d))
  printLn (parity n False)
  printLn (parity (S n) False)
