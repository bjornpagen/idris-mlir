-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
-- What the stock Idris prints of Fuzz.twoHosts, which this program,
-- compiled by idris-mlir with the five modules beside it, must print too.
module Main

import Prelude
import Fuzz

main : IO ()
main = putStr Fuzz.twoHosts
