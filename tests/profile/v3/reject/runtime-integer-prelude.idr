-- expect: runtime integer, line 10
module Main

-- An Integer made from a runtime Int would exist at runtime. The failing
-- primitive is inside the Prelude's Cast implementation; the error is
-- reported at the user's definition that reached it.

import Prelude

main : IO ()
main = do
  c <- getChar
  printLn (the Integer (cast (ord c)))
