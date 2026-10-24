module Main

-- A tail call whose callee lays its result out otherwise than its caller
-- does is made a tail call by a copy of the callee keyed to the open
-- layout. g returns four strings, a vector whose length its type fixes; f
-- and r return n of them, n read at run time, so where n is 4 a call of g
-- that is the last thing either does calls the copy of g keyed open.
-- f asks for that copy as soon as g is final. e, which calls g at g's own
-- layout and asks for no copy, is final in the same wave, so r, which
-- waits on g and e alone, is decided in the wave the copy f asked for is
-- taken up, before it: r reads what the copy gives from the table, as it
-- stands then, and is decided again wherever the copy's own decisions
-- restate it, so its call is made at the signature the copy has. Where n
-- is 4 and its count is 0, r ends in a call of e, whose vector is laid out
-- otherwise too, made a tail call by a copy of e keyed open.
-- Each function recurses, so each stays a function wherever another is
-- inlined into it; main prints every string f and r give, so no result is
-- left unread. Where n is 4, g's recursion runs a million steps before it
-- gives its strings, and elsewhere f's and r's do.

import Prelude
import Data.Vect

g : Nat -> String -> Vect 4 String
g Z s = [s, s ++ "!", s, s]
g (S k) s = g k s

f : (n : Nat) -> Nat -> Vect n String
f (S (S (S (S Z)))) k = g k ("a" ++ "b")
f n Z = replicate n "f"
f n (S k) = f n k

e : Nat -> String -> Vect 4 String
e Z t = g 2 t
e (S k) t = e k t

r : (n : Nat) -> Nat -> String -> Vect n String
r (S (S (S (S Z)))) Z t = e 3 t
r (S (S (S (S Z)))) (S k) t = g k ("a" ++ "b")
r n Z t = replicate n t
r n (S k) t = r n k t

readNat : IO Nat
readNat = go 0
  where
    go : Nat -> IO Nat
    go acc = do
      c <- getChar
      if isDigit c then go (acc * 10 + cast (ord c - 48)) else pure acc

main : IO ()
main = do
  n <- readNat
  printLn (toList (f n 1000000))
  printLn (toList (r n 1000000 (show n)))
  printLn (toList (r n 0 (show n)))
