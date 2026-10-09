module Main

-- The registry's pointer hooks: a pointer is a handle of the runtime's.
-- The null pointer is the null handle, a literal; a test of null is the
-- handle operation; a cast between pointer types is the handle it is
-- given; and a string handle's string is read with the handle operation,
-- as base's getEnv reads a variable's value. translate.check finds none of
-- them called in full Core, and the program prints expected-stdout.

import Prelude
import System
import System.File

nullity : AnyPtr -> (Int, Int)
nullity h =
  let p : Ptr String = prim__castPtr h
  in (prim__nullAnyPtr (prim__forgetPtr p), prim__nullPtr p)

main : IO ()
main = do
  printLn (nullity prim__getNullAnyPtr)
  let FHandle input = stdin
  printLn (nullity input)
  ignore (setEnv "IDRIS_MLIR_HANDLE" "read" True)
  printLn !(getEnv "IDRIS_MLIR_HANDLE")
