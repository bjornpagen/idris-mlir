-- stdout: 1\n
module Main
import Prelude

-- An unreachable definition outside the profile is neither checked nor compiled.
big : Integer
big = 12345678901234567890

main : IO ()
main = printLn (1)
