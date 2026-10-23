module Main

-- A NaN is one Double with itself. The type checker compared two Double
-- constants by the program's `==`, by which no NaN equals any Double,
-- itself included, so it refused a type whose two sides evaluate to one
-- NaN. Definitional equality now reads a Double by its bits, and a NaN's
-- are its own. `nanA` and `nanB` are written apart, so the sides of
-- `itself` are one term only once both are evaluated, each to the NaN
-- that 0.0 / 0.0 is on the host that runs the compiler. `unequal` checks
-- that they are evaluated to a NaN, which the program's `==` still finds
-- unequal to itself. Checking the types is the test. The run compares the
-- two by `==`, as the program does, and prints False.

import Prelude

%default total

nanA : Double
nanA = 0.0 / 0.0

nanB : Double
nanB = 0.0 / 0.0

0 unequal : (nanA == nanA) = False
unequal = Refl

0 itself : nanA = nanB
itself = Refl

main : IO ()
main = printLn (nanA == nanB)
