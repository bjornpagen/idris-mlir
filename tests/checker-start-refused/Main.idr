-- expect: elaboration, line 10
-- message: %start
module Main
import Prelude

-- `%start` names the expression a REPL session runs first. This compiler
-- runs no REPL, so the pragma is refused where it is written, never
-- ignored.

%start main

main : IO ()
main = putStrLn "main"
