-- expect: signal, line 11
-- message: System.Signal.collectSignal
module Main

import Prelude
import System.Signal

-- A signal collected to be handled later arrives at a time the world does
-- not name, so signals are outside the language: the definition that uses
-- one is refused.
watch : IO ()
watch = do
  Right () <- collectSignal SigINT
    | Left _ => putStrLn "not collected"
  putStrLn "collected"

main : IO ()
main = watch
