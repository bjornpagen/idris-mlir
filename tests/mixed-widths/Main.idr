module Main

import Prelude
import Prog

main : IO ()
main = do
  printLn Prog.result
  printLn (byte least)
  printLn (short least)
  printLn (word least)
  printLn (int least)
  printLn (byte greatest)
  printLn (short greatest)
  printLn (word greatest)
  printLn (int greatest)
  printLn (byte past)
  printLn (short past)
  printLn (word past)
  printLn (int past)
