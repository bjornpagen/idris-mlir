-- stdout: ok\n
module Main

import IdrisMLIR.IO

-- rule: PROF-IO-1, PROF-IO-2, PROF-GEN-5, FE-ENTRY-4, SEM-PROG-2
main : IO ()
main = putStrLn "ok"
