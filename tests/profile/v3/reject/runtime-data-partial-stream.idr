-- expect: runtime data, line 13
module Main

-- A stream consumer the Prelude declares covering, `takeBefore`, in a
-- closed call that never ends: no element of the stream passes 40, so
-- compile-time evaluation stops the call once it has spent its budget, and
-- leaves it to runtime, where the list it takes would be built. The list is
-- built in the Prelude; the rejection is reported at the user's definition
-- that reached it, `main`, as runtime-integer-prelude is.

import Prelude

main : IO ()
main = printLn (sum (takeBefore (> 40) (countFrom (the Int 1) (* 1))))
