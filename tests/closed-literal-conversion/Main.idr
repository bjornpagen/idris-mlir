module Main

import Prelude
import Prog

main : IO ()
main = do
  printLn (number Prog.viaString)
  putStrLn Prog.viaDouble
