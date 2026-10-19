-- expect: runtime closure, line 29
module Main

import Prelude

-- An implementation that closes over a runtime value is passed as that
-- value (implementation-runtime-scope); a
-- constructor's constraint holds one implementation for the whole program,
-- not a value, so it cannot hold one. near/ holds the term alone and gives
-- the implementation to the function that shows it.

data Term : List String -> Type where
  Var : Nat -> Term names

nameAt : List String -> Nat -> String
nameAt (n :: _) Z = n
nameAt (_ :: ns) (S k) = nameAt ns k
nameAt [] _ = "?"

{names : _} -> Show (Term names) where
  show (Var i) = nameAt names i

data Shown : Type -> Type where
  MkShown : Show a => a -> Shown a

unshown : Shown a -> String
unshown (MkShown x) = show x

shown : (names : List String) -> Term names -> Shown (Term names)
shown names t = MkShown t

main : IO ()
main = do
  x <- getLine
  putStrLn (unshown (shown [x] (Var 0)))
