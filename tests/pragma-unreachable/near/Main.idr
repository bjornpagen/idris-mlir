module Main
import Prelude

main : IO ()
main = printLn (the Int 0)

-- The refused program without %inline: an unreached definition costs
-- nothing.
unused : Int
unused = 1
