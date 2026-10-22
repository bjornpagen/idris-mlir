-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| How a case of a program test says its run ends, read once into the
||| specification's ending (Facts.idr): the status a parent must see, an
||| exit code or a signal, which lib/e2e.sh compares with the shell's:
|||
|||     runtests --case-status <case>   `code <n>` or `signal <name>`
|||
||| The stderr the run must write is the case's committed bytes
||| (`expected-stderr`), the runtime's line for a crash among them, which
||| e2e.sh compares byte for byte: no message is rendered or parsed here.
||| A case whose `expected-ending` is no ending fails here, naming the
||| file, so a misspelt ending is never read as a return.
module Case

import Data.String
import System

import Facts
import Files

%default covering

endingOrDie : (dir : String) -> IO Ending
endingOrDie dir = do
  text <- readIfThere (dir ++ "/expected-ending")
  case endingOf text of
    Right e => pure e
    Left why => die why

||| `--case-status <case>`: how the run of the case must end.
export
caseStatus : (dir : String) -> IO ()
caseStatus dir = putStrLn (statusLine !(endingOrDie dir))
