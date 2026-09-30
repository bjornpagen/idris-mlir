module Main

-- A sum of naturals, 500 levels deep. `tri 500` is a closed call, so it is
-- evaluated at compile time; `tri m`, with m read at runtime, runs. Each
-- `+` is Nat's plus and `printLn` shows through natToInteger: both are
-- arithmetic on Nat's representation, a big, so the program neither
-- recurses once per unit (natToInteger of 125250 did, and overflowed the
-- stack) nor takes time quadratic in the sum.

import Prelude

tri : Nat -> Nat
tri Z = Z
tri (S k) = S k + tri k

main : IO ()
main = do
  c <- getChar
  let m = the Nat (cast (the Int (cast (ord c) - 48)) * 100)
  printLn (tri 500)
  printLn (tri m)
  printLn (tri m * tri m)
