module Greeting

import IdrisMLIR.IO

export
greet : String -> IO ()
greet who = putStrLn (prim__strAppend "hello, " who)
