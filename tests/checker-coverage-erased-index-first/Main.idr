module Main

-- Erased proofs, each covering: `Marker.mappedDrops`, `Contracts.
-- mappedContracts` (fourteen constructors against ten) and
-- `CaseBlock.erasedReduces`, whose case block's scrutinee fixes the
-- intermediate term its environment binds first. The tree an erased
-- definition's coverage is checked by split the indices first, so an index
-- ended at values no clause has with the arguments that determine it
-- unsplit, a case nothing refuted: the pinned Idris reported each not
-- covering, naming only impossible cases, and walked `mappedContracts`'s
-- nested defaults past minutes. That tree now takes first the arguments a
-- run keeps. Checking the modules this one imports is the test; the
-- program only runs.
-- The stock Idris is patched for it (upstream/110-coverage-erased-index-
-- first); the type checker has the change as its own code, and this test
-- checks it.

import Prelude
import Marker
import Contracts
import CaseBlock

main : IO ()
main = putStrLn "checked"
