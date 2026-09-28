-- exit: 0
-- stdout: x\n
module Main

-- From v3 the proof combinators of Builtin (sym, trans, replace) are
-- admitted; only its escape hatches are not. Equal's `x` is a value
-- parameter, which does not tell instances apart.

import Prelude

main : IO ()
main = case sym (Refl {x = 'a'}) of
         Refl => putStrLn "x"
