module Main
import Prelude
import Data.Buffer

read : Buffer -> IO Int
read buf = cast <$> getBits8 buf 0

main : IO ()
main = do
  Just buf <- newBuffer 1
    | Nothing => pure ()
  line <- getLine
  setBits8 buf 0 (cast (the Int (cast line)))
  printLn !(read buf)
