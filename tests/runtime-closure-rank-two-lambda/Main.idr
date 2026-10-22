module Main

-- A lambda passed where a polymorphic function is asked for, applied at
-- two types by the function it is passed to, which shows a term in a
-- scope that holds a name read at run time. The lambda ignores its
-- argument, so each application shows the same term.

import Prelude

data Tm : List String -> Type where
  V : Nat -> Tm ns
  A : Tm ns -> Tm ns -> Tm ns

nameAt : List String -> Nat -> String
nameAt (n :: _) Z = n
nameAt (_ :: ns) (S k) = nameAt ns k
nameAt [] _ = "?"

[showTm] {ns : List String} -> Show (Tm ns) where
  show (V i) = nameAt ns i
  show (A f a) = "(" ++ show @{showTm} f ++ " " ++ show @{showTm} a ++ ")"

showAt : ({0 a : Type} -> a -> String) -> String
showAt f = f (the Int 1) ++ " " ++ f "two"

main : IO ()
main = do
  x <- getLine
  putStrLn (showAt (\_ => show @{showTm {ns = [x]}} (V 0)))
  putStrLn (showAt (\_ => show @{showTm {ns = ["f", x]}} (A (V 0) (V 1))))
