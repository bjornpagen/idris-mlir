module Main

import Compiler.Common
import Idris.Driver
import IdrisMLIR.Inspect

main : IO ()
main = mainWithCodegens [("core-inspect", inspector)]
