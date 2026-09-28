-- expect: PROF-TYPE-4 line 11
module Main

-- rule: PROF-TYPE-4, SEM-EXCL-2, DIAG-LOC-1
-- An Integer made from a runtime Int would exist at runtime. The failing
-- primitive is inside the Prelude's Cast implementation; the error is
-- reported at the user's definition that reached it.

import Prelude

main : IO ()
main = do
  c <- getChar
  printLn (the Integer (cast (ord c)))
