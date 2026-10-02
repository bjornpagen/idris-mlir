-- Data.IORef loads System.Concurrency and System.Info, whose foreign
-- functions (threads, the system's name) have no meaning in this
-- compiler. Nothing here reaches them, so loading them is no reason to
-- reject the program.
module Main

import Prelude
import Data.IORef

main : IO ()
main = printLn (the Int 42)
