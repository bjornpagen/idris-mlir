-- expect: elaboration, line 11
-- message: zip'
module Main

-- A program Idris's type checker rejects: the build stops at Idris's
-- error, and the pipeline neither runs nor adds a refusal of its own.

import Prelude

lz : List (Int, Int)
lz = zip' [1, 2] [3, 4]

main : IO ()
main = printLn lz
