-- expect: elaboration, line 23
module Main

-- A definition that misses a case though an equation in its argument holds
-- of the part beside it: `upToOne (MkHead Nothing [7]) ([7] ** (Refl,
-- LTESucc LTEZero))` is a call the clause does not match. The coverage
-- check now also reads one part of a dependent pair under what another
-- holds, here `ts = _ :: _`; the case missing has a bound, `LTE (length
-- ts) 1`, still inhabited when so read (`LTESucc LTEZero` for a list of
-- one), so the search must not find it empty, and the definition is
-- refused as not covering, where it is declared.
-- The stock Idris is patched for the check (upstream/111-coverage-nested-
-- empty-type), and refuses this; the type checker has the change as its
-- own code, and this test checks that it refuses this too.

import Prelude
import Data.Nat

%default total

data Head = MkHead (Maybe Nat) (List Nat)

upToOne : (r : Head) -> (ts : List Nat ** (r = MkHead Nothing ts, LTE (length ts) 1)) -> Bool
upToOne (MkHead Nothing []) ([] ** (Refl, _)) = True

partial
main : IO ()
main = do
  printLn (upToOne (MkHead Nothing []) ([] ** (Refl, LTEZero)))
  printLn (upToOne (MkHead Nothing [7]) ([7] ** (Refl, LTESucc LTEZero)))
