-- exit: 0
-- stdout: 55\n
module Main

-- Codata: an infinite Stream is a closure of no arguments, forced by name,
-- and taken apart only as far as it is forced. The closed call of `take` is
-- evaluated at compile time and the list never exists at runtime. (So is
-- one of a consumer the Prelude declares covering, such as `takeBefore`,
-- when it ends: accept/partial-stream. One that never ends
-- stays, and its list would be built at runtime:
-- reject/runtime-data-partial-stream.)

import Prelude

main : IO ()
main = do
  printLn (sum (take 10 (countFrom (the Int 1) (+ 1))))
