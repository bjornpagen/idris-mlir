module Main

import Prelude

-- Writing a program writes each declaration, and a declaration writes its
-- bindings, a list of named terms, through the implementations for lists
-- and pairs, which write each term in turn, and a term its own bindings:
-- out is requested at List Decl and, below it, at List (String, Term), as
-- Idris's toBuf is requested at List Name and, below it, at
-- List (Name, Term). Each implementation that runs is one function at the
-- types the program writes, so the recursion closes over finitely many.

interface Out a where
  out : a -> String

Out String where
  out s = s

(Out a, Out b) => Out (a, b) where
  out (x, y) = out x ++ "=" ++ out y

Out a => Out (List a) where
  out [] = ""
  out (x :: xs) = "[" ++ out x ++ "]" ++ out xs

data Term = Ref String | Let (List (String, Term)) Term

Out Term where
  out (Ref n) = n
  out (Let bs t) = "let " ++ out bs ++ " in " ++ out t

data Decl = Bind (List (String, Term))

Out Decl where
  out (Bind bs) = "bind " ++ out bs

main : IO ()
main = putStrLn ("" <+> out [Bind [("x", Ref "y")], Bind [("z", Let [("w", Ref "x")] (Ref "w"))]])
