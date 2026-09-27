module Main

import Prelude

-- rule: SEM-IO-1, SEM-IO-7, IDR-EFF-2, LOW-IO-1, LOW-TAIL-3
-- Reads and writes alternate in the world chain. The Prelude's getChar reads
-- one byte and returns character 255 at the end of input (SEM-IO-7); its
-- putChar agrees with the reference only on ASCII (SEM-IO-2), so the input
-- is ASCII.
echo : IO ()
echo = do
  c <- getChar
  case prim__eq_Char c '\255' of
    1 => pure ()
    _ => do
      putChar c
      echo

main : IO ()
main = echo
