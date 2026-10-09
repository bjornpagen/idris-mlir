module Main

-- A loop over an array's index space whose integer ops fit 32 bits but
-- would compute something else there: the residues of i - 2 by 7 as
-- Bits64. The remainder reads its operand unsigned, so at the first two
-- indices it reads -2 and -1 as 2^64 - 2 and 2^64 - 1 (residues 0 and 1);
-- a 32-bit remainder would read 2^32 - 2 and 2^32 - 1 (residues 2 and 3).
-- The compiler vectorizes the loop and keeps its lanes 64-bit, so the
-- numbers are the 64-bit residues.

import Prelude
import Linear.Notation
import Linear.Array

residues : Int -> Array Bits64
residues n = generate n (\i => cast (i - 2) `mod` 7)

readInt : IO Int
readInt = go 0
  where
    go : Int -> IO Int
    go acc = do
      c <- getChar
      if isDigit c then go (acc * 10 + cast (ord c - 48)) else pure acc

main : IO ()
main = do
  n <- readInt
  printLn (freeze (residues n) Linear.Array.sum)
  printLn (freeze (residues n) (\a => iread a 0))
  printLn (freeze (residues n) (\a => iread a 1))
