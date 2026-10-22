-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
-- The checks the generators state of themselves, compiled by idris-mlir
-- with the six modules beside it (Sem and Facts among them, which Fuzz
-- and Prims import):
-- each a line `<owner>: <name>: ok`, or `failed` where the compiled
-- program computes otherwise.
module Main

import Prelude
import Data.String
import Gen
import Fuzz
import Lazy

line : String -> (String, Bool) -> String
line owner (name, holds) = owner ++ ": " ++ name ++ ": " ++ (if holds then "ok" else "failed")

main : IO ()
main = putStr $ unlines $
  map (line "gen") Gen.checks
    ++ map (line "fuzz-check") Fuzz.checkerChecks ++ map (line "lazy-check") Lazy.checkerChecks
