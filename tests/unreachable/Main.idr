module Main

import Prelude
import System

-- A definition the program does not reach is neither checked nor compiled:
-- `shell` runs a process of its own, which the profile refuses where it is
-- reached, and nothing reaches it.
shell : IO Int
shell = system "true"

main : IO ()
main = printLn (the Int 1)
