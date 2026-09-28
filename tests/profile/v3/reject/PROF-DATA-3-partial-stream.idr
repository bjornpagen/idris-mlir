-- expect: PROF-DATA-3 line 12
module Main

-- A closed call of a partial function is never evaluated: the Prelude
-- declares `takeBefore` covering, so the list it takes from the stream
-- would be built at runtime. The list is built in the Prelude; the
-- rejection is reported at the user's definition that reached it, `main`,
-- as PROF-TYPE-4-prelude-integer is.

import Prelude

main : IO ()
main = printLn (sum (takeBefore (> 40) (countFrom (the Int 1) (* 2))))
