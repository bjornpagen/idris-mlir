-- expect: raw pointer, line 12
-- message: System.FFI.malloc
module Main

import Prelude
import System.FFI

-- Memory from the C library's allocator is outside the language: a
-- pointer of base is a handle of the runtime's, and each reference the
-- compiler keeps is a heap value it counts. The definition that allocates
-- is refused.
scratch : IO ()
scratch = do
  _ <- malloc 16
  putStrLn "allocated"

main : IO ()
main = scratch
