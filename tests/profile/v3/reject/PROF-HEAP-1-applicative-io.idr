-- expect: PROF-HEAP-1 line 13
module Main

-- rule: PROF-HEAP-1, DIAG-LOC-1
-- The Prelude's `(*>)` for IO is its Applicative default,
-- `map (const id) a <*> b`: running `a` yields a function, which a
-- specialized action would have to return at runtime. `for_` and
-- `traverse_` are built from it. Rejected, not miscompiled; `>>` and `do`
-- work.

import Prelude

main : IO ()
main = putStrLn "a" *> putStrLn "b"
