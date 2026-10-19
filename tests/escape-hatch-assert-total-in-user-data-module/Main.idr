-- expect: escape hatch, line 7
-- A totality assertion in a user module named like a module of base: it is
-- the user's escape hatch, not a trusted library's. The line is
-- Data/Evil.idr's.
module Main

import Prelude
import Data.Evil

main : IO ()
main = printLn (count 3)
