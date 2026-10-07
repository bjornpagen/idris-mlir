-- expect: deprecated, line 7
-- message: use bufferData'
module Main
import Prelude
import Data.Buffer

bytes : Buffer -> IO (List Int)
bytes buf = bufferData buf

main : IO ()
main = do
  Just buf <- newBuffer 1
    | Nothing => pure ()
  printLn !(bytes buf)
