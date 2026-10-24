module Main

-- Case blocks on a bind whose type is fixed only through constraints
-- postponed while its arguments were checked: `given`'s `Maybe String`
-- against the bind's `?m ?a` is outside the pattern fragment until the
-- search for `Monad ?m` fails on `m` and makes it invertible, which
-- happens when constraints are next solved, after the case has read its
-- scrutinee's type. The case read `?m ?b` and refused each definition:
-- "Can't infer type for case scrutinee". It now solves the postponed
-- constraints before it gives the type up, and the type is `Maybe
-- Integer`. `parsed` is the same with a function of no implicit argument:
-- the bind alone fixes nothing sooner.
-- The stock Idris is patched for it (upstream/117-case-scrutinee-
-- postponed-constraints); the type checker has the change as its own
-- code, and this test checks it.

import Prelude
import Data.String

seed : Maybe String -> Integer
seed given =
  case given >>= parseInteger of
    Just s => s
    Nothing => 0

parse : String -> Maybe Integer
parse = parseInteger

parsed : Maybe String -> Integer
parsed given =
  case given >>= parse of
    Just s => s
    Nothing => 0

main : IO ()
main = do
  printLn (seed (Just "42"))
  printLn (seed (Just "x"))
  printLn (seed Nothing)
  printLn (parsed (Just "-7"))
  printLn (parsed Nothing)
