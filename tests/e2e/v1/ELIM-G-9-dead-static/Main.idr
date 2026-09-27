module Main

import Prelude

main : IO ()
main = do
  let unused = \x => prim__add_Int x 1
  let action = putStrLn "never run"
  putStrLn "only this"
