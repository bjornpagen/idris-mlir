module Main

import Data.Linear.Array

-- The continuation's result type is unconstrained, so the "linear" array
-- escapes the scope of newArray and becomes an ordinary, shareable value.
leak : LinArray Int
leak = newArray 4 (\arr => arr)

-- Closure capture: a linear lambda returns a thunk that hands the array out
-- again on every call.
leakF : () -> LinArray Int
leakF = newArray 4 (\arr => \u => arr)

main : IO ()
main = do
  let a = leak
      (_ # a1) = write a 0 10
      (_ # a2) = write a 0 20    -- the "consumed" a is written again
      (v # _)  = mread a1 0
  printLn v                      -- the pure reading of a1 sees 20: aliasing
  let f = leakF
      (_ # b1) = write (f ()) 1 7
      (w # _)  = mread (f ()) 1
  printLn w
