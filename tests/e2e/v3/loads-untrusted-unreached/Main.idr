-- Data.IORef loads System.Concurrency and Control.Linear.LIO loads System,
-- neither of which the compiler trusts. Nothing here reaches them, so
-- loading them is no reason to reject the program.
module Main

import Prelude
import Data.IORef
import Control.Linear.LIO

main : IO ()
main = printLn (the Int 42)
