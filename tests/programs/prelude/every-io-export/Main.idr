module Main

-- Every run-time export of Prelude.IO the compiler admits, each used
-- (covers): console input and output, in IO and in a monad of the
-- program's own through its HasIO, and running a primitive action, each
-- result printed so that Chez checks what it computes.

import Prelude

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
