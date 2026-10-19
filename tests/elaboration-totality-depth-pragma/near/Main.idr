module Main

-- The refused program without `%totality_depth`.

import Prelude

main : IO ()
main = printLn (the Int 1)
