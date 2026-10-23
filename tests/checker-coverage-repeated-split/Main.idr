module Main

-- Proofs that index a table by a kind, with a wildcard for the kinds the
-- index rules out. The case tree splits the kind, then the proof, and the
-- tree of the last clause, copied under the proof's default, splits the
-- proof again. The walk that proposes missing cases lost there what the
-- first split found, and the pinned Idris reported `f Read (There _)` not
-- matched, a case no value has (the second element of [Read, Write] is
-- Write), and refused the module. `g` splits one level further down: an
-- argument of the proof split twice is split again.
-- The stock Idris is patched for it (upstream/104-coverage-repeated-split);
-- the type checker has the change as its own code, and this test checks
-- it.

import Prelude
import Data.List.Elem

%default total

data Kind = Read | Write | Allocate | Free

f : (k : Kind) -> Elem k [Read, Write] -> Nat
f Read Here = 0
f Write (There Here) = 1
f _ (There (There later)) = absurd later

g : (k : Kind) -> Elem k [Read, Write, Free] -> Nat
g Read Here = 0
g Write (There Here) = 1
g Free (There (There Here)) = 2
g _ (There (There (There later))) = absurd later

main : IO ()
main = do
  printLn (f Read Here)
  printLn (f Write (There Here))
  printLn (g Read Here)
  printLn (g Write (There Here))
  printLn (g Free (There (There Here)))
