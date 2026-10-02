module Main

-- A stream consumer the Prelude declares covering, `takeBefore`, in a
-- closed call that never ends: no element of the stream passes 40, so
-- compile-time evaluation stops the call once it has spent its budget and
-- leaves it to runtime, where the list it takes is built on the heap. The
-- program compiles; it never ends, so it is not run.

import Prelude

main : IO ()
main = printLn (sum (takeBefore (> 40) (countFrom (the Int 1) (* 1))))
