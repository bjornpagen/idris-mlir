-- expect: PROF-TYPE-4 line 20
module Main

-- rule: SEM-EVAL-6, PROF-GEN-4
-- A closed call of a partial function is never evaluated (SEM-EVAL-6):
-- Idris does not prove `euclid` terminating, so `euclid 1071 462` stays a
-- call, and its Integer would exist at runtime. The program was part of
-- e2e/v3/compile-time-evaluation and e2e/v3/prelude-math before
-- compile-time evaluation ran only total code, and was accepted then (a
-- PROF-GEN-4 exception). The Integer operations are the Prelude's
-- (Integral Integer), reached from `euclid`, and the rejection is reported
-- at its body, line 20 (DIAG-LOC-1).

import Prelude

euclid : Integral a => Eq a => a -> a -> a
euclid a b = if b == 0 then a else euclid b (a `mod` b)

main : IO ()
main = printLn (euclid (the Integer 1071) 462)
