module Main

-- A natural counted down to zero, a hundred million steps read at runtime.
-- Its only other state is a Bool, so once one test on entry has found the
-- natural small the loop runs on machine words: mlir.expect states that
-- some loop of the program holds no big at all.

import Prelude

parity : Nat -> Bool -> Bool
parity Z odd = odd
parity (S k) odd = parity k (not odd)

main : IO ()
main = do
  c <- getChar
  let n = the Nat (cast (the Int (cast (ord c) - 48)) * 100000000)
  printLn (parity n False)
  printLn (parity (S n) False)
