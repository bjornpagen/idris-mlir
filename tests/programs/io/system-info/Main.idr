module Main

import Prelude
import System.Info

main : IO ()
main = do
  putStrLn os
  putStrLn (if isWindows then "yes" else "no")
  putStrLn codegen
  Just n <- getNProcessors
    | Nothing => putStrLn "none"
  putStrLn (show n)
