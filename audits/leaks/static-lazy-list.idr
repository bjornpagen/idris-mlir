-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
-- Leak L2, reduced: the list is folded into static data whose first lazy
-- tail is a static memo cell; toList's force settles a cell of its frame
-- into it, and the cells after it are lost when show's calls overwrite the
-- dead frame: live cells n-2 at exit (3 here). See audits/leaks.md.
module Main
import Prelude
import Data.List.Lazy
from : Nat -> LazyList Char
from Z = []
from (S n) = (chr (cast (S n) + 96)) :: from n

main : IO ()
main = putStrLn (show (pack (toList (from 5))))
