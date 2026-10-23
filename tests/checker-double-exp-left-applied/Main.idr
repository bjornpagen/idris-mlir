-- expect: elaboration, line 18
module Main

-- A type that holds only if the type checker computes `exp 1.0`. The last
-- digit of `exp`, as of every Double function of the C library, is each
-- library's, so the checker computed it by the library of the host that
-- runs the compiler, which need not be the target's. It now leaves `exp`
-- applied, and the type, `prim__doubleExp 1.0` against a constant, is
-- refused: "Can't solve constraint between: 2.718281828459045 and
-- prim__doubleExp 1.0". The stock Idris computes it and accepts this; the
-- type checker leaves it applied, and this test checks that it refuses.

import Prelude

%default total

0 folded : exp 1.0 = 2.718281828459045
folded = Refl

main : IO ()
main = putStrLn "unreached"
