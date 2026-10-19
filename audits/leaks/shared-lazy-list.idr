-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
-- Leak L2's crash: a lazy list read at run time and forced twice. The first
-- traversal settles a frame cell into a heap memo cell the caller keeps; the
-- second reads the dead frame: SIGSEGV for every input of 2 or more. See
-- audits/leaks.md.
module Main
import Prelude
import Data.List.Lazy
from : Nat -> LazyList Char
from Z = []
from (S n) = (chr (cast (S n) + 96)) :: from n

main : IO ()
main = do
  l <- getLine
  let xs = from (cast l)
  putStrLn (pack (toList xs))
  putStrLn (pack (toList xs))
