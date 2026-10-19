-- expect: pragma, line 6
-- message: Data/Evil.idr:6:
-- A user module named like a module of base is still the user's: trust
-- follows the package Idris loaded a module from, never its name. The
-- line is Data/Evil.idr's, which the message pins.
module Main

import Prelude
import Data.Evil

main : IO ()
main = printLn (double 21)
