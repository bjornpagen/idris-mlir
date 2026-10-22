module Main

-- An implementation can close over a runtime value: `Show (Term names)`
-- shows a variable by the name its scope gives it, so it takes the scope
-- at runtime, as the type checker shows and serialises its
-- terms (`{vars : _} -> Show (Term vars)`). Which implementation it is
-- stays known at compile time, only the scope is passed, and the
-- implementation for lists takes it on to the implementation it is given.
-- The implementation for pairs is given two, each with its own scope,
-- which it gets as one value.

import Prelude

data Term : List String -> Type where
  Var : Nat -> Term names
  Lam : (x : String) -> Term (x :: names) -> Term names
  App : Term names -> Term names -> Term names

nameAt : List String -> Nat -> String
nameAt (n :: _) Z = n
nameAt (_ :: ns) (S k) = nameAt ns k
nameAt [] _ = "?"

{names : _} -> Show (Term names) where
  show (Var i) = nameAt names i
  show (Lam x sc) = "\\" ++ x ++ ". " ++ show sc
  show (App f a) = "(" ++ show f ++ " " ++ show a ++ ")"

record Scoped where
  constructor MkScoped
  scope : List String
  terms : List (Term scope)

describe : Scoped -> String
describe s = show s.terms

main : IO ()
main = do
  x <- getLine
  putStrLn (show (the (Term []) (Lam x (Lam "y" (App (Var 1) (Var 0))))))
  putStrLn (describe (MkScoped [x, "b"] [Var 0, App (Var 1) (Var 0)]))
  putStrLn (show (the (Term [x], Term ["q", x]) (Var 0, App (Var 0) (Var 1))))
