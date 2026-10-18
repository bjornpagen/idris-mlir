-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
-- Fuzz.twoHosts, which this program, compiled by idris-mlir with the five
-- modules beside it, must print as the committed expected-stdout holds it.
module Main

import Prelude
import Fuzz

main : IO ()
main = putStr Fuzz.twoHosts
