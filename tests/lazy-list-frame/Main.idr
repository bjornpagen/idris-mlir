-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
-- A lazy list's next tail, a memo cell its force makes, moves into the memo
-- cell the force ran on, which outlives the force's frame: so the next
-- tail is never a cell of that frame (the rules of the frame, IR/Lifetimes.h).
-- When it was, the static list below lost the cells after its first tail
-- (live cells n-2 at exit) and the list read at run time, forced twice,
-- read its second time through a dead frame (SIGSEGV for every length of
-- 2 or more). Each prints its characters, and no cell is left.
module Main
import Prelude
import Data.List.Lazy

from : Nat -> LazyList Char
from Z = []
from (S n) = (chr (cast (S n) + 96)) :: from n

main : IO ()
main = do
  putStrLn (show (pack (toList (from 5))))
  l <- getLine
  let xs = from (cast l)
  putStrLn (pack (toList xs))
  putStrLn (pack (toList xs))
