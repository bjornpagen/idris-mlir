module Greet

import Prelude

export
greet : String -> IO ()
greet who = putStrLn (prim__strAppend "hello from " who)
