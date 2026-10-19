module Main

import Prelude

data Term : List String -> Type where
  Var : Nat -> Term names

nameAt : List String -> Nat -> String
nameAt (n :: _) Z = n
nameAt (_ :: ns) (S k) = nameAt ns k
nameAt [] _ = "?"

{names : _} -> Show (Term names) where
  show (Var i) = nameAt names i

data Shown : Type -> Type where
  MkShown : a -> Shown a

unshown : Show a => Shown a -> String
unshown (MkShown x) = show x

shown : (names : List String) -> Term names -> Shown (Term names)
shown names t = MkShown t

main : IO ()
main = do
  x <- getLine
  putStrLn (unshown (shown [x] (Var 0)))
