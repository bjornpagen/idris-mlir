-- expect: runtime integer, line 13
module Main

-- A closed call of a partial function is never evaluated: Idris does not
-- prove `euclid` terminating, so `euclid 1071 462` stays a call, and its
-- Integer would exist at runtime. The Integer operations are the
-- Prelude's (Integral Integer), reached from `euclid`, and the rejection
-- is reported at its body.

import Prelude

euclid : Integral a => Eq a => a -> a -> a
euclid a b = if b == 0 then a else euclid b (a `mod` b)

main : IO ()
main = printLn (euclid (the Integer 1071) 462)
