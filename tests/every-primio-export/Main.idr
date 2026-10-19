module Main

-- Every run-time export of PrimIO the compiler admits and user code may
-- write, each used (covers): IO's and PrimIO's pure and bind, the
-- conversions between them and a primitive action's result, and the
-- pointers, which are the runtime's handles: the null one, and standard
-- input's, which is not null. Each result is printed so that what it
-- computes is checked.

import Prelude
import System.File

-- A primitive action of the program's own, threading the world it is
-- given.
counted : Int -> PrimIO Int
counted n w = MkIORes (n * 2) w

-- Whether a handle is null, asked of the handle and of a typed pointer
-- cast from it and forgotten again: a cast is the handle itself.
nullity : AnyPtr -> (Int, Int)
nullity h =
  let p : Ptr Int = prim__castPtr h
  in (prim__nullAnyPtr (prim__forgetPtr p), prim__nullPtr p)

main : IO ()
main = do
  io_bind (io_pure (the Int 1)) printLn
  x <- fromPrim (counted 21)
  printLn x
  y <- fromPrim (prim__io_bind (prim__io_pure (the Int 3)) (\v => prim__io_pure (v + 1)))
  printLn y
  fromPrim (toPrim (putStrLn "toPrim"))
  z <- fromPrim (prim__io_bind (toPrim getLine) (\s => counted (cast (length s))))
  printLn z
  printLn (nullity prim__getNullAnyPtr)
  let FHandle input = stdin
  printLn (nullity input)
