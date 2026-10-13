module Main

-- A match whose alternatives cover every constructor of its data type has
-- no default alternative: the frontend writes none, so no pass meets a
-- path no value takes.

import Prelude

data Colour = Red | Green | Blue

name : Colour -> String
name Red = "red"
name Green = "green"
name Blue = "blue"

next : Colour -> Colour
next Red = Green
next Green = Blue
next Blue = Red

main : IO ()
main = do
  putStrLn (name (next Red))
  putStrLn (name (next (next Red)))
  putStrLn (name (next (next (next Red))))
