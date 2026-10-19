module Main
import Prelude

-- The refused program without %inline: %default is a pragma the profile
-- admits.
%default total

one : Int
one = 1

main : IO ()
main = printLn one
