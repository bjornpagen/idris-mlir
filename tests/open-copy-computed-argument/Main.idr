module Main

-- A tail call whose callee lays its result out otherwise than its caller
-- does is made a tail call by a copy of the callee keyed to the open
-- layout, which returns the result laid out as its caller returns it. g
-- returns four strings, a vector whose length its type fixes; f and h
-- return n of them, n read at run time. Where n is 4, the last thing each
-- does is call g, and the four strings g gives would be laid out again
-- after the call, which would make it no tail call: each calls the copy
-- of g keyed open instead, and that call is a tail call.
-- The string each passes g is computed from two literals, which the
-- compiler may compute into static data where g counts the string it
-- takes, and the strings g gives are made of it. Where a key stating that
-- hold would give its result at less than the caller reads, the key
-- states what it can, the open layout, and the string crosses at the hold
-- g takes, so the tail call is made either way.
-- f and h ask for the one copy, whose calls are made at the signature it
-- has when each asks, whatever the decisions of its component made of it,
-- and each is a tail call.
-- Each function recurses, so each stays a function wherever another is
-- inlined into it; main calls f and h where no tail is lost and prints
-- every string they give, so no result is left unread. g's recursion runs
-- a million steps before it gives its strings.

import Prelude
import Data.Vect

g : Nat -> String -> Vect 4 String
g Z s = [s, s ++ "!", s, s]
g (S k) s = g k s

f : (n : Nat) -> Nat -> Vect n String
f (S (S (S (S Z)))) k = g k ("a" ++ "b")
f n Z = replicate n "f"
f n (S k) = f n k

h : (n : Nat) -> Nat -> Vect n String
h (S (S (S (S Z)))) k = g (S k) ("a" ++ "b")
h n Z = replicate n "h"
h n (S k) = h n k

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
  printLn (toList (h n 999999))
