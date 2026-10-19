-- expect: finalizer, line 10
-- message: Prelude.IO.onCollectAny
module Main

import Prelude

-- A collector finalizer runs when a collector frees a value. The heap here
-- is counted and nothing runs at a collection, so a finalizer is outside
-- the language: the definition that registers one is refused.
register : IO ()
register = do
  _ <- onCollectAny prim__getNullAnyPtr (\_ => putStrLn "freed")
  putStrLn "registered"

main : IO ()
main = register
