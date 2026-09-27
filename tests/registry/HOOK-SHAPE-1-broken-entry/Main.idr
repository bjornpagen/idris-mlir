module Main

-- rule: HOOK-SHAPE-1
-- Any program that imports the Prelude loads the modules of the registry's
-- entries, so every entry is validated when it compiles.

import Prelude

main : IO ()
main = putStrLn "hello"
