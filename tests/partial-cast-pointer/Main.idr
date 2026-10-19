module Main

-- The pointer casts applied below their arity, as functions handed to map:
-- each partial application is a closure whose body is the saturated cast,
-- the handle it is given, so the program means what it means at full
-- arity. The null handle cast to a typed pointer and back is still null,
-- and each of the three standard handles, cast and forgotten, is still not
-- null.

import Prelude
import System.File

main : IO ()
main = do
  let FHandle input = stdin
      FHandle output = stdout
      FHandle errors = stderr
      handles = [prim__getNullAnyPtr, input, output, errors, prim__getNullAnyPtr]
      typed : List (Ptr String)
      typed = map prim__castPtr handles
      back = map prim__forgetPtr typed
  printLn (map prim__nullAnyPtr back)
