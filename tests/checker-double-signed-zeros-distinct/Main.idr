-- expect: elaboration, line 19
module Main

-- A type that holds only if 0.0 and -0.0 are one Double. They are two
-- IEEE 754 values, which `1.0 / x` tells apart, an infinity of each sign,
-- so a proof that they are one proves `Void`. The type checker compared
-- two Double constants by the program's `==`, by which 0.0 equals -0.0,
-- and accepted this. Definitional equality now reads a Double by its bits,
-- and the type, the constant 0.0 against the constant -0.0 that
-- `negate 0.0` evaluates to, is refused. The stock Idris compares by `==`
-- and accepts this; the type checker reads the bits, and this test checks
-- that it refuses.

import Prelude

%default total

0 zeros : the Double 0.0 = negate 0.0
zeros = Refl

main : IO ()
main = putStrLn "unreached"
