module Main

-- The refused program with main an IO that runs MyIO's action: MyIO is a
-- value like any other, and only main must be an IO.

import Prelude

data MyIO : Type -> Type where
  MkMyIO : (1 fn : PrimIO a) -> MyIO a

run : MyIO a -> IO a
run (MkMyIO fn) = fromPrim fn

main : IO ()
main = run (MkMyIO (toPrim (putStrLn "hi")))
