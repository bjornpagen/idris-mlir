-- exit: 0
-- stdout: 55\n
module Main

-- rule: SEM-REC-2, SEM-REC-1, ELIM-EVAL-1
-- Codata: an infinite Stream is a closure of no arguments, forced by name,
-- and taken apart only as far as it is forced. The Prelude's ranges are
-- built from streams (`[1 .. 10]` is `takeUntil (>= 10) (countFrom 1 (+ 1))`),
-- and the closed total call is evaluated at compile time.
-- `printLn (sum (takeBefore (> 40) (countFrom (the Int 1) (* 2))))` is gone
-- since the cutover (docs/cutover.md 4.3, decision 7.2, a PROF-GEN-4
-- exception): the Prelude declares `takeBefore` covering, so it is not
-- evaluated and its list would be built at runtime. It is the reject
-- fixture profile/v3/reject/PROF-DATA-3-partial-stream, and its line of
-- output, 63, left the header.

import Prelude

main : IO ()
main = do
  printLn (sum [the Int 1 .. 10])
