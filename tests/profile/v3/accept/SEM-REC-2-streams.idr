-- exit: 0
-- stdout: 63\n55\n
module Main

-- rule: SEM-REC-2, SEM-REC-1, ELIM-G-16
-- Codata: an infinite Stream is a compile-time value like a list, taken
-- apart only as far as it is forced. The Prelude's ranges are built from
-- streams (`[1 .. 10]` is `takeUntil (>= 10) (countFrom 1 (+ 1))`).

import Prelude

main : IO ()
main = do
  printLn (sum (takeBefore (> 40) (countFrom (the Int 1) (* 2))))
  printLn (sum [the Int 1 .. 10])
