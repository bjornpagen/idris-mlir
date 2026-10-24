module Main

import Prelude
import Data.Fin

-- base's `restrict` gives `fromInteger` the proof its bound asks for, at
-- quantity 0, by `believe_me`: an argument that never runs, the library's
-- proof, which it is trusted for as for a definition of quantity 0. The
-- program calls `restrict`, which runs, and never the `believe_me`, so it
-- compiles; a user's own `believe_me` in such an argument is still refused
-- (escape-hatch-believe-me-in-proof).

main : IO ()
main = do
  printLn (finToNat (restrict 4 7))
  printLn (finToNat (restrict 2 10))
