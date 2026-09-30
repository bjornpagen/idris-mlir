-- expect: escape hatch, line 11
-- A totality assertion in a user module named like a module of base: it is
-- the user's escape hatch, not a trusted library's. The line is Main's call.
module Main

import Prelude
import Data.Evil

main : IO ()
main = printLn (count 3)
