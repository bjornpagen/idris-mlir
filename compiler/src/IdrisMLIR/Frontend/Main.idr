module IdrisMLIR.Frontend.Main

import Idris.Driver
import IdrisMLIR.Frontend.Inspect

main : IO ()
main = mainWithCodegens [("core-inspect", inspector)]
