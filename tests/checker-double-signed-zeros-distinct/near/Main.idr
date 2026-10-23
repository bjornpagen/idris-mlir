module Main

-- The refused program with the program's comparison in place of
-- definitional equality: by IEEE 754's `==`, which the checker evaluates
-- as the runtime does, 0.0 equals -0.0.

import Prelude

%default total

0 zeros : (the Double 0.0 == negate 0.0) = True
zeros = Refl

main : IO ()
main = printLn (the Double 0.0 == negate 0.0)
