module Main

-- The refused program with its number an Int, whose text every host
-- writes as its sign and digits, so the checker still computes it.

import Prelude

%default total

0 folded : cast {to = String} (the Int 10) = "10"
folded = Refl

main : IO ()
main = putStrLn (cast {to = String} (the Int 10))
