-- expect: pragma, line 11
-- message: %extern
module Main

import Prelude

-- An extern declared in user code, a name only a backend gives a meaning:
-- refused where it is written, naming the pragma, though nothing reaches
-- it; it is never ignored. near/ defines the same name in Idris.

%extern
prim__shout : String -> PrimIO ()

main : IO ()
main = putStrLn "hello"
