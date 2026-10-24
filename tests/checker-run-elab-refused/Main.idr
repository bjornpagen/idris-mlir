-- expect: elaboration, line 14
-- message: %runElab
module Main
import Prelude
import Language.Reflection

%language ElabReflection

-- `%runElab` runs an elaborator script while the program is elaborated,
-- and a script may read and write files. This compiler runs no script, so
-- the pragma is refused where it is written, before any script is parsed
-- or run, even with the language extension a script asks for.

%runElab logMsg "elab" 0 "a script ran"

main : IO ()
main = putStrLn "main"
