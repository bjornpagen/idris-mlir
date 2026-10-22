module Main

-- Base's own natToFinLT, at 3 below 10, searches LT 3 10, that is LTE 4
-- 10, then LTE 3 9, down to LTE 0 6: each goal's numbers are smaller than
-- the one before, so no earlier goal is held in a later one, and the
-- search finds its proof.

import Prelude
import Data.Fin

main : IO ()
main = printLn (finToNat (natToFinLT 3 {n = 10}))
