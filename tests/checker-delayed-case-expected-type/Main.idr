module Main

-- Pattern-matching lambdas, and a lambda over a case, checked at a Lazy
-- function type, as `maybe`'s second argument is. The lambda's body, a case
-- on its argument, is elaborated later, at the type its hole is given,
-- which the rest of the application fixes. The pinned Idris elaborated the
-- case block at a fresh type instead, abstracted over its own scrutinee,
-- which no clause could solve, and refused each definition: "Can't solve
-- constraint between: String and ?caseTy".
-- The stock Idris is patched for it (upstream/107-delayed-case-expected-
-- type); the type checker has the change as its own code, and this test
-- checks it.

import Prelude

first : Maybe (Nat, String) -> String
first x = maybe "" (\(n, m) => m ++ show n) x

second : Maybe (String, String) -> String
second x = maybe "" (\(n, m) => m) x

bar : Lazy (Bool -> Nat)
bar = \x => case x of
  True => 1
  False => 0

main : IO ()
main = do
  putStrLn (first (Just (7, "n=")))
  putStrLn (first Nothing)
  putStrLn (second (Just ("a", "b")))
  printLn ((Force bar) True)
  printLn ((Force bar) False)
