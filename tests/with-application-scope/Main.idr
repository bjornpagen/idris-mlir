module Main

-- A with block called again, on a smaller value, from its own right-hand
-- side, from a local definition, and in a record update's field. Each is
-- accepted, compiles and runs: before the checker's fix the last two were
-- refused, the application left unrewritten. Each goes down to Z, from 5
-- and from a number read at run time, and gives Z or the box unchanged.

import Prelude

record Box where
  constructor MkBox
  size : Nat

direct : Nat -> Nat
direct n with (n)
  direct n | Z = Z
  direct n | (S k) = direct n | k

local : Nat -> Nat
local n with (n)
  local n | Z = Z
  local n | (S k) = go k
    where
      go : Nat -> Nat
      go m = local n | m

update : Nat -> Box -> Box
update n b with (n)
  update n b | Z = b
  update n b | (S k) = { size := size (update n b | k) } b

main : IO ()
main = do
  printLn (direct 5)
  printLn (local 5)
  printLn (size (update 5 (MkBox 7)))
  line <- getLine
  let k = the Nat (cast (the Int (cast line)))
  printLn (direct k, local k, size (update k (MkBox 7)))
