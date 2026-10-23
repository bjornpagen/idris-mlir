module Main

-- A parameters block whose second parameter's type is an `if` on the
-- first. An `if` is a case block, named by the full name of the position
-- it is made at; a parameters block's types were checked at no position
-- of the context, so the block was named by a bare index the context
-- never gave, which a TTC cannot hold: "INTERNAL ERROR: Can't write
-- resolved name". The block's types are now checked at a position of
-- their own, which has a name, so the case block is named by it. Checking
-- the block, writing the module, and running a definition under the block
-- with each choice of the first parameter, each call's second argument
-- checked against what the case block gives for it, is the test.

import Prelude

%default total

-- `x` is erased: its type, which holds the case block, is what is tested,
-- and a value whose representation follows a Bool is no part of it.
parameters (b : Bool) (0 x : if b then Nat else Bool)
  kind : String
  kind = if b then "a number" else "a truth value"

main : IO ()
main = do putStrLn (kind True 3)
          putStrLn (kind False True)
