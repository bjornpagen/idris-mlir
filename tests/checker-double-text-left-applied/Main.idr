-- expect: elaboration, line 21
module Main

-- A type that holds only if the type checker computes the text of a
-- Double. The runtime writes a Double's text, and the stock host's agrees
-- with it only because the runtime was written to match; the checker wrote
-- it by the host that runs the compiler. It now leaves a Double's text
-- applied, and the type, `prim__cast_DoubleString 0.1` against a string,
-- is refused: "Can't solve constraint between: "0.1" and
-- prim__cast_DoubleString 0.1". A type reaches the text through `cast`,
-- since `show` of a Double reaches it through a private function of the
-- Prelude, which no type here unfolds. The stock Idris writes it and
-- accepts this; the type checker leaves it applied, and this test checks
-- that it refuses.

import Prelude

%default total

0 folded : cast {to = String} 0.1 = "0.1"
folded = Refl

main : IO ()
main = putStrLn "unreached"
