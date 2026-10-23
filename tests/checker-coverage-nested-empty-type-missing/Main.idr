-- expect: elaboration, line 19
module Main

-- A definition that misses a case: `below 1 (5, LTESucc LTEZero)` is a call
-- the clause does not match. The coverage check now also finds a type
-- empty when each constructor that fits it takes an argument of an empty
-- type; the case missing has a pair whose `LTE (S _) 1` is inhabited
-- through the same constructors, so the search must not find it empty, and
-- the definition is refused as not covering, where it is declared.
-- The stock Idris is patched for the check (upstream/111-coverage-nested-
-- empty-type), and refuses this; the type checker has the change as its
-- own code, and this test checks that it refuses this too.

import Prelude
import Data.Nat

%default total

below : (c : Nat) -> (Nat, LTE c 1) -> Bool
below _ (_, LTEZero) = True

partial
main : IO ()
main = do
  printLn (below 0 (5, LTEZero))
  printLn (below 1 (5, LTESucc LTEZero))
