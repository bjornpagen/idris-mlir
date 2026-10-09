-- expect: process, line 10
-- message: System.system
module Main

import Prelude
import System

-- A shell command run as a process of its own is outside the language for
-- now: the definition that runs one is refused.
shell : IO Int
shell = system "true"

main : IO ()
main = printLn !shell
