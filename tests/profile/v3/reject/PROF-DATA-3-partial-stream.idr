-- expect: PROF-DATA-3 line 17
module Main

-- rule: SEM-EVAL-6, SEM-REC-2, PROF-GEN-4, DIAG-LOC-1
-- A closed call of a partial function is never evaluated (docs/cutover.md
-- A23): the Prelude declares `takeBefore` covering, so the list it takes
-- from the stream would be built at runtime. The program was part of
-- profile/v3/accept/SEM-REC-2-streams before the cutover, and was accepted
-- then (4.3, decision 7.2, a PROF-GEN-4 exception). The list is built in
-- the Prelude; the rejection is reported at the user's definition that
-- reached it, `main`, as PROF-TYPE-4-prelude-integer is.

import Prelude

main : IO ()
main = printLn (sum (takeBefore (> 40) (countFrom (the Int 1) (* 2))))
