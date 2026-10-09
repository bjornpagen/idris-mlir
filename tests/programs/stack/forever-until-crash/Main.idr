module Main

-- forever, the loop that never returns (base has none; this is the usual
-- one): its action, then forever again, in tail position. The profile takes
-- no System.exitWith, so the program ends the way a partial one does, on
-- the input its match has no case for: the end of the input, after eleven
-- hundred lines of a thousand letters, each line written as a dot, on the
-- 1 MiB stack the harness gives.

import Prelude

covering
forever : IO () -> IO b
forever act = act >> forever act

partial
step : IO ()
step = do
  c <- getChar
  case ord c == 255 of
    False => when (c == '\n') (putStr ".")

partial
main : IO ()
main = forever step
