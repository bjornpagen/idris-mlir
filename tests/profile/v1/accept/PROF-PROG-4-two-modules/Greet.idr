module Greet

import IdrisMLIR.IO

export
greet : String -> IO ()
greet who = putStrLn (prim__strAppend "hello from " who)
