-- exit: 0
-- stdout: 55\n
module Main

-- rule: SEM-REC-2, SEM-REC-1, ELIM-EVAL-1
-- Codata: an infinite Stream is a closure of no arguments, forced by name,
-- and taken apart only as far as it is forced. `take` is total, so the
-- closed call is evaluated at compile time and the list never exists at
-- runtime. (The Prelude's ranges, `[1 .. 10]`, consume their stream with
-- `takeUntil`, which it declares covering: a range is never evaluated, and
-- its list would be built at runtime. That is the reject fixture
-- profile/v3/reject/PROF-DATA-3-covering-range.)

import Prelude

main : IO ()
main = do
  printLn (sum (take 10 (countFrom (the Int 1) (+ 1))))
