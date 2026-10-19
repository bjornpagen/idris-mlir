module Main

-- Every run-time export of Prelude.IO the compiler admits, each used
-- (covers): console input and output, in IO and in a monad of the
-- program's own through its HasIO, running a primitive action, and
-- reading a string the runtime holds (prim__getString, which base's getEnv
-- reads a variable's value with), each result printed so that what it
-- computes is checked.

import Prelude
import System

record App a where
  constructor MkApp
  runApp : IO a

Functor App where
  map f (MkApp io) = MkApp (map f io)

Applicative App where
  pure x = MkApp (pure x)
  MkApp f <*> MkApp x = MkApp (f <*> x)

Monad App where
  MkApp x >>= k = MkApp (x >>= \a => runApp (k a))

HasIO App where
  liftIO = MkApp

-- The console through App's HasIO.
greet : App Int
greet = do
  putStr "app: "
  name <- getLine
  putStrLn ("hello, " ++ name)
  c <- getChar
  putChar c
  putCharLn '!'
  print (the Int 1)
  putChar '\n'
  printLn [c, c]
  liftIO (pure (cast (length name)))

main : IO ()
main = do
  n <- runApp greet
  printLn n
  line <- getLine
  putStrLn ("io: " ++ line)
  c <- getChar
  printLn c
  liftIO {io = IO} (putStrLn "liftIO")
  liftIO1 (putStrLn "liftIO1")
  five <- primIO (toPrim (pure (the Int 5)))
  printLn five
  primIO1 (toPrim (putStrLn "primIO1"))
  ignore (setEnv "IDRIS_MLIR_IO" "held" True)
  held <- getEnv "IDRIS_MLIR_IO"
  printLn held
