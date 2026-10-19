module Main

import Prelude
import Prog

partial
main : IO ()
main = do
  traverse_ putStrLn Prog.specials
  traverse_ putStrLn Prog.ends
