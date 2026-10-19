-- expect: deprecated, line 7
-- message: use getBits8
module Main
import Prelude
import Data.Buffer

read : Buffer -> IO Int
read buf = getByte buf 0

main : IO ()
main = do
  Just buf <- newBuffer 1
    | Nothing => pure ()
  printLn !(read buf)
