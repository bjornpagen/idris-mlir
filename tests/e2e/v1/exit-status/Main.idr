module Main

import IdrisMLIR.IO

-- rule: SEM-IO-5, SEM-IO-4
main : IO ()
main = do
  putStr "before exit"
  exit 300
  putStrLn "never"
