-- expect: runtime integer, line 12
module Main

-- A closed call of a partial function that never ends: compile-time
-- evaluation stops `count 0` once it has spent its budget and leaves it to
-- runtime, where its Integer would exist. The rejection is reported at its
-- body.

import Prelude

count : Integer -> Integer
count n = if n < 0 then n else count (n + 1)

main : IO ()
main = printLn (count 0)
