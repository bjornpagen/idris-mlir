module Main

-- The pointer casts applied below their arity, as functions handed to map:
-- each partial application is a closure whose body is the saturated cast,
-- the handle it is given, so the program means what it means at full
-- arity. The null handle cast to a typed pointer and back is still null,
-- and so is stdin's handle, cast and forgotten, still stdin's.

import Prelude
import System.File

main : IO ()
main = do
  let FHandle input = stdin
      handles = [prim__getNullAnyPtr, input, prim__getNullAnyPtr]
      typed : List (Ptr String)
      typed = map prim__castPtr handles
      back = map prim__forgetPtr typed
  printLn (map prim__nullAnyPtr back)
