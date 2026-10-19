-- expect: deprecated, line 11
-- message: getBits8
module Main
import Prelude
import Data.Buffer

-- getByte is deprecated: wherever it is reached the program is refused,
-- and the refusal names its replacement. near/ is this program reading the
-- byte with getBits8, which is limited to a byte as getByte's Int is not:
-- the byte written is the input's value modulo 256.
read : Buffer -> IO Int
read buf = getByte buf 0

main : IO ()
main = do
  Just buf <- newBuffer 1
    | Nothing => pure ()
  line <- getLine
  setBits8 buf 0 (cast (the Int (cast line)))
  printLn !(read buf)
