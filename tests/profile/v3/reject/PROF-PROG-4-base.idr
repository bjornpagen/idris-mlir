-- expect: PROF-PROG-4 line 6
-- packages: base
module Main

import IdrisMLIR.IO
import System.File

main : IO ()
main = putStrLn "hi"
