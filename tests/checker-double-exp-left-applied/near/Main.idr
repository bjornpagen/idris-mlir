module Main

-- The refused program with its function the root, which IEEE 754 rounds
-- correctly, so the checker still computes it.

import Prelude

%default total

0 folded : sqrt 2.0 = 1.4142135623730951
folded = Refl

main : IO ()
main = printLn (sqrt 2.0)
