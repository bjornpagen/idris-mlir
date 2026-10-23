module Main

-- `()` writes either the unit type `Unit` or its one value `MkUnit`,
-- chosen by the type the site is expected to have:
-- - a universe: the unit type;
-- - any other type already known: the unit value;
-- - a type not yet known: the one reading that fits there, and where both
--   fit, as they always do for `()`, the unit value, the syntax's default.
--
-- `which` tells which reading a site took by the type it was given: an
-- implementation at `Type`, the unit type's type, and one at `()`, the
-- unit value's. With both, either reading finds an implementation, so only
-- the rule decides what it prints.

import Prelude

%default total

interface Reading t where
  which : (0 _ : t) -> String

Reading Type where
  which _ = "the unit type"

-- An implementation's head is a type: `()` is `Unit`.
Reading () where
  which _ = "the unit value"

-- A signature is expected to be a type: `()` is `Unit`; the definition is
-- expected to have that type, known and no universe: `()` is `MkUnit`.
nothing : ()
nothing = ()

main : IO ()
main = do
  -- Expected `Type`: `Unit`.
  putStrLn (which {t = Type} ())
  -- Expected `Unit`: `MkUnit`.
  putStrLn (which {t = ()} ())
  -- Expected type unknown, both readings fit (`Unit : Type`,
  -- `MkUnit : Unit`): the default, `MkUnit`.
  putStrLn (which ())
  -- Expected type unknown, `printLn`'s argument at any type: the default,
  -- `MkUnit`, shown "()". (Read as `Unit`, it would be shown at `Type`,
  -- which has no `Show`.)
  printLn ()
  printLn nothing
