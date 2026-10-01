-- expect: library, line 9
-- packages: base
module Main

import Prelude
import Control.App
import Control.App.FileIO

contents : Has [PrimIO, Exception IOError] e => App e String
contents = readFile "stop"

-- Control.App.FileIO is trusted and loads System.File, which is not.
-- Loading it is not what is rejected: readFile reaches System.File, and
-- that is.
main : IO ()
main = run (handle contents (\s => primIO (putStrLn s)) (\err : IOError => primIO (putStrLn "no file")))
