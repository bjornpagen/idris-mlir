module Main

import IdrisMLIR.IO

-- rule: SEM-IO-3, IDR-EFF-2, LOW-IO-1
echo : IO ()
echo = do
  c <- getChar
  case prim__eq_Char c '\0' of
    1 => pure ()
    _ => do
      putChar c
      echo

main : IO ()
main = echo
