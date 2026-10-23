module Main

-- `(x ** p)`, with no type written for `x`, writes either the dependent
-- pair type `DPair _ (\x => p)`, `x` bound over `p` and its type inferred,
-- or the dependent pair `MkDPair x p`, `x` a value in scope; chosen by the
-- type the site is expected to have:
-- - a universe: the type;
-- - any other type already known: the pair;
-- - a type not yet known: the one reading that fits there.
-- `(x : a ** p)`, which names `x`'s type, is only ever the type.
--
-- `which` tells which reading a site took by the type it was given: an
-- implementation at `Type`, the type of the dependent pair type, and one
-- at `(n : Nat ** Type)`, the type of a dependent pair of a Nat and a type.

import Prelude

%default total

data Tag : Nat -> Type where
  MkTag : (n : Nat) -> Tag n

interface Reading t where
  which : (0 _ : t) -> String

Reading Type where
  which _ = "the dependent pair type"

Reading (n : Nat ** Type) where
  which _ = "the dependent pair"

-- A signature is expected to be a type: `(n ** Tag n)` is
-- `DPair Nat (\n => Tag n)`, `n`'s type inferred from `Tag`'s index. The
-- definition is expected to have that type, known and no universe:
-- `(k ** MkTag k)` is `MkDPair k (MkTag k)`, whose first component is the
-- argument.
tagged : (k : Nat) -> (n ** Tag n)
tagged k = (k ** MkTag k)

-- `k`, a Nat, is in scope at each site, so `(k ** Tag k)` has both
-- readings: the type binds a `k` of its own over `Tag k`; the pair is of
-- this `k` and the type `Tag k`.
readings : (k : Nat) -> IO ()
readings k = do
  -- Expected `Type`: the type, `DPair Nat (\k => Tag k)`.
  putStrLn (which {t = Type} (k ** Tag k))
  -- Expected `DPair Nat (\n => Type)`: the pair, `MkDPair k (Tag k)`.
  putStrLn (which {t = (n : Nat ** Type)} (k ** Tag k))

-- `b` is a Bool, so the pair `MkDPair b (Tag b)` does not fit, `Tag` being
-- indexed by a Nat, while the type binds a `b` of its own, a Nat.
apart : (b : Bool) -> IO ()
apart b =
  -- Expected type unknown: the one reading that fits, the type,
  -- `DPair Nat (\b => Tag b)`.
  putStrLn (which (b ** Tag b))

main : IO ()
main = do
  readings 2
  apart True
  printLn (DPair.fst (tagged 3))
