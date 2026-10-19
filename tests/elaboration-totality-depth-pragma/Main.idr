-- expect: elaboration, line 10
module Main

-- The count of constructors the termination checker looks under is gone,
-- and with it its pragma: a program that writes `%totality_depth` is
-- refused where it writes it, by Idris's parser, before anything checks.

import Prelude

%totality_depth 7

main : IO ()
main = printLn (the Int 1)
