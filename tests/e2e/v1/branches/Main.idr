module Main

import Prelude

data Answer = Yes | No

say : Answer -> String
say Yes = "yes"
say No = "no"

main : IO ()
main = do
  putStrLn (say Yes)
  putStrLn (say No)
  putStrLn (prim__strAppend (say No) (prim__strAppend "/" (say Yes)))
