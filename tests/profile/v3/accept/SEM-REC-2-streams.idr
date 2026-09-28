-- exit: 0
-- stdout: 55\n
module Main

-- Codata: an infinite Stream is a closure of no arguments, forced by name,
-- and taken apart only as far as it is forced. `take` is total, so the
-- closed call is evaluated at compile time and the list never exists at
-- runtime. (A stream consumer the Prelude declares covering, such as
-- `takeBefore`, is never evaluated, and its list would be built at
-- runtime. That is the reject fixture
-- profile/v3/reject/PROF-DATA-3-partial-stream.)

import Prelude

main : IO ()
main = do
  printLn (sum (take 10 (countFrom (the Int 1) (+ 1))))
