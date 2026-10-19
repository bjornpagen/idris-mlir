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

-- A term nested as deep as the input says: each level is a Let whose
-- binding holds the level below, and the implementations that write it are
-- the same few at every depth.
nest : Nat -> Term
nest Z = Ref "x"
nest (S k) = Let [("v", nest k)] (Ref "v")

main : IO ()
main = do
  line <- getLine
  putStrLn ("" <+> out [Bind [("x", Ref "y")], Bind [("z", Let [("w", Ref "x")] (Ref "w"))]])
  putStrLn (out [Bind [("z", nest (integerToNat (cast line)))]])
