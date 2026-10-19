module Main

-- A Bits8 of 128 or more as a natural and as an Integer: its value, not a
-- negative number, and no poison. The byte is the length of the line read,
-- modulo 256, made at run time, so no fold computes it, and the conversion
-- is the runtime's, whose result word is the number's tagged form: the
-- range the byte's value has is the value's, never the word's. The two
-- conversions agree, and the byte is past 127 exactly when the Integer is.

import Prelude

main : IO ()
main = do
  w <- getLine
  let b = the Bits8 (cast (length w))
  let n = the Nat (cast b)
  let i = the Integer (cast b)
  printLn n
  printLn i
  printLn (i > 127, b > 127)
  printLn (cast n == i)
