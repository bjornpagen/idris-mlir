-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
-- audits/bugs.md's linear-string-iterator, reduced (-p mlir-linear): live
-- cells 3 at exit. The same cause as static-lazy-list.idr. See
-- audits/leaks.md.
module Main
import Prelude
import Data.List.Lazy
import Linear.String.Iterator
main : IO ()
main = putStrLn (show (pack (toList (Iterator.unpack "hello"))))
