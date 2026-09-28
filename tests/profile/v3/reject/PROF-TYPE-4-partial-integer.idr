-- expect: PROF-TYPE-4 line 19
module Main

-- rule: SEM-EVAL-6, PROF-GEN-4
-- A closed call of a partial function is never evaluated (docs/cutover.md
-- A23): Idris does not prove `euclid` terminating, so `euclid 1071 462`
-- stays a call, and its Integer would exist at runtime. The program was
-- part of e2e/v3/compile-time-evaluation and e2e/v3/prelude-math before the
-- cutover, and was accepted then (4.3, decision 7.2, a PROF-GEN-4
-- exception). The Integer operations are the Prelude's (Integral Integer),
-- reached from `euclid`, where the rejection is reported (DIAG-LOC-1).
-- Unverified until idris-mlir-cc exists: the line is predicted from the
-- rule that a C++ rejection is reported at the innermost user definition,
-- and from `euclid` coming before the root, into which `main` is inlined,
-- in the module.

import Prelude

euclid : Integral a => Eq a => a -> a -> a
euclid a b = if b == 0 then a else euclid b (a `mod` b)

main : IO ()
main = printLn (euclid (the Integer 1071) 462)
