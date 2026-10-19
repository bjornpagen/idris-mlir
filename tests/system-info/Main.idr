module Main

-- System.Info on the host it runs on: an operating system's name, no
-- Windows, this code generator, and every processor the host has.

import Prelude
import System.Info

main : IO ()
main = do
  putStrLn (if os == "" then "no name" else "a name")
  putStrLn (if isWindows then "yes" else "no")
  putStrLn codegen
  Just n <- getNProcessors
    | Nothing => putStrLn "none"
  putStrLn (show n)
