module Main

import Prelude

-- A sum past the small range (2^62): the program reaches the runtime's
-- large bigs as well as its small cases.
main : IO ()
main = printLn (the Integer 4611686018427387903 + 4611686018427387903)
