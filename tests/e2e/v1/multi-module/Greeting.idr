module Greeting

import Prelude

export
greet : String -> IO ()
greet who = putStrLn (prim__strAppend "hello, " who)
