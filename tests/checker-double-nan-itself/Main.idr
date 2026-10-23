module Main

-- A NaN is one Double with itself. `0.0 / 0.0` is a NaN: IEEE 754 fixes
-- that it is one, not its sign or payload, which differ between targets,
-- so the type checker leaves the division applied, as it leaves every
-- Double operation whose result is a NaN, and no constant is a NaN.
-- `nanA` and `nanB` are written apart, so the sides of `itself` are one
-- term only once both are evaluated, each to the division applied to two
-- constants 0.0. The checker finds two Double constants one double when
-- `==` finds them equal and finds their reciprocals equal, which is their
-- bits for every Double but a NaN, which `==` finds unequal to itself: had
-- it folded the division to a NaN constant, it would refuse `itself`.
-- Checking the types is the test. The run compares the two by `==`, as
-- the program does, and prints False: their value is a NaN.

import Prelude

%default total

nanA : Double
nanA = 0.0 / 0.0

nanB : Double
nanB = 0.0 / 0.0

0 itself : nanA = nanB
itself = Refl

main : IO ()
main = printLn (nanA == nanB)
