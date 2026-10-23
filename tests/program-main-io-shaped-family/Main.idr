-- expect: program, line 16
-- message: main must be an IO action
module Main

-- MyIO has IO's shape, one constructor holding a primitive action, but it
-- is not IO: a program runs main as `unsafePerformIO main`, which takes an
-- IO of any type and nothing of another family, so a main of MyIO is
-- refused, whatever its shape. near/ runs the same action through MyIO
-- from a main of IO.

import Prelude

data MyIO : Type -> Type where
  MkMyIO : (1 fn : PrimIO a) -> MyIO a

main : MyIO ()
main = MkMyIO (toPrim (putStrLn "hi"))
