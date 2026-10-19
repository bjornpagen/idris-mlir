-- expect: pragma, line 6
-- A user module named like a module of base is still the user's: trust
-- follows the package Idris loaded a module from, never its name. The
-- line is Data/Evil.idr's.
module Main

import Prelude
import Data.Evil

main : IO ()
main = printLn (double 21)
