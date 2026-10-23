module Main

-- A partial match on a type taken at quantity many: at a type its clause
-- covers it gives that clause's value, and at any other it ends as a
-- missing case does.

import Prelude

partial
f : Type -> Nat
f Nat = 1

partial
main : IO ()
main = do
  printLn (f Nat)
  printLn (f Bool)
