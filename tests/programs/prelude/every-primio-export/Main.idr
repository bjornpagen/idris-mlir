module Main

-- Every run-time export of PrimIO the compiler admits and user code may
-- write, each used (covers): IO's and PrimIO's pure and bind, the
-- conversions between them and a primitive action's result, each result
-- printed so that what it computes is checked.

import Prelude

-- A primitive action of the program's own, threading the world it is
-- given.
counted : Int -> PrimIO Int
counted n w = MkIORes (n * 2) w

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
