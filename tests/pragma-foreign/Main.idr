-- expect: pragma, line 12
-- message: %foreign
module Main

import Prelude

-- A C symbol declared in user code: %foreign and the C ABI are outside the
-- language, so the declaration is refused where it is written, naming the
-- pragma, though nothing reaches it; it is never ignored. near/ defines
-- the same name in Idris.

%foreign "C:puts,libc"
puts : String -> PrimIO Int

main : IO ()
main = putStrLn "hello"
