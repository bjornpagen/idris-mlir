module Main

-- A closed call of a partial function is evaluated at compile time, as a
-- total one is: Idris does not prove `euclid` terminating, but
-- `euclid 1071 462` ends, so its Integer is a constant and never exists at
-- runtime. The Integer operations are the Prelude's (Integral Integer),
-- reached from `euclid`.

import Prelude

euclid : Integral a => Eq a => a -> a -> a
euclid a b = if b == 0 then a else euclid b (a `mod` b)

main : IO ()
main = printLn (euclid (the Integer 1071) 462)
