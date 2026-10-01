-- Data.IORef loads System.Concurrency and System.Info, which the compiler
-- does not trust. Nothing here reaches them, so loading them is no reason
-- to reject the program.
module Main

import Prelude
import Data.IORef

main : IO ()
main = printLn (the Int 42)
