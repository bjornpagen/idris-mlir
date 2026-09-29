-- exit: 0
-- stdout: 63\n
module Main

-- A stream consumer the Prelude declares covering, `takeBefore`, in a
-- closed call that ends: it is evaluated at compile time, and the list it
-- takes from the infinite stream never exists at runtime.

import Prelude

main : IO ()
main = printLn (sum (takeBefore (> 40) (countFrom (the Int 1) (* 2))))
