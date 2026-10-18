module Main

import Prelude

-- check traverses an Either (List e) (List Int) in IO: traverse is a
-- method of Traversable (Either (List e)) with a constraint of its own,
-- Applicative IO. e reaches the implementation one List deeper than the
-- message main writes, once, and never deeper.

start : e -> List Int -> Either (List e) (List Int)
start err [] = Left [err]
start err xs = Right xs

check : Show e => e -> List Int -> IO (Either (List e) (List Int))
check err xs = traverse (\ys => do printLn (length ys); pure ys) (start err xs)

report : Show e => Either (List e) (List Int) -> IO ()
report (Left es) = putStrLn ("failed: " ++ show es)
report (Right ys) = printLn ys

main : IO ()
main = do
  let err = Just (Just (Just (Just (Just "empty"))))
  a <- check err []
  report a
  b <- check err [1, 2, 3]
  report b
