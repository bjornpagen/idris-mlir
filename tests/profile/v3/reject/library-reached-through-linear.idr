-- expect: library, line 10
-- packages: linear
module Main

import Prelude
import Control.Linear.LIO

-- Control.Linear.LIO is trusted and loads System, which is not. Loading
-- it is not what is rejected: die1 reaches System.die, and that is.
stop : L IO ()
stop = die1 {a = ()} "stop" `bind` \u => case u of () => pure ()
  where
    bind : L1 IO () -@ (() -@ L IO ()) -@ L IO ()
    bind = (>>=)

main : IO ()
main = run stop
