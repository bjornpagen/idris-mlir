-- stdout: ok\n
module Main

import Prelude

-- rule: PROF-IO-4, PROF-GEN-5, FE-ENTRY-4, SEM-PROG-2
-- The Prelude's IO library: its putStrLn is %inline over a %foreign
-- primitive, and the compiler honours only what PROF-LIB-2 allows.
main : IO ()
main = putStrLn "ok"
