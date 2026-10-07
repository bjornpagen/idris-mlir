-- expect: deprecated, line 7
-- message: use setBits8
module Main
import Prelude
import Data.Buffer

write : Buffer -> IO ()
write buf = setByte buf 0 1

main : IO ()
main = do
  Just buf <- newBuffer 1
    | Nothing => pure ()
  write buf
