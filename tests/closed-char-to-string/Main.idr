module Main

import Prelude
import Prog

main : IO ()
main = do
  putStrLn Prog.eAcute
  traverse_ putStrLn Prog.ends
