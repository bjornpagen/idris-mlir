module Main

import Prelude
import System

-- The refused program without the process: the status a true command
-- exits with, without running one.
shell : IO Int
shell = pure 0

main : IO ()
main = printLn !shell
