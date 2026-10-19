module Main

-- A Bits8 of 128 or more as a natural and as an Integer: its value, not a
-- negative number, and no poison. The byte is 200, made at run time from
-- the length of the line read (4, times 50), so no fold computes it, and
-- the conversion is the runtime's, whose result word is the number's
-- tagged form: the range the byte's value has is the value's, never the
-- word's.

import Prelude

main : IO ()
main = do
  w <- getLine
  let b = the Bits8 (cast (length w)) * 50
  let n = the Nat (cast b)
  let i = the Integer (cast b)
  printLn n
  printLn i
  printLn (i > 127)
  printLn (n == 200)
