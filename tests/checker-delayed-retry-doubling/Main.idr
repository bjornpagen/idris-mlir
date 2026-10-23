-- expect: elaboration, line 55
module Main

-- A do block of sixteen pattern binds over a linear machine, each bind's
-- match a delayed elaborator nested in the one before, whose last line uses
-- `b`, which the first bind binds to a value, as a type. The error is
-- recoverable, so each level of the nest retried the level inside it in a
-- recoverable pass and again in an all-errors pass, and the failure at the
-- bottom ran twice for every level above it before its error was reported:
-- on the pinned Idris, time doubling per bind, past the step limit here. A
-- delayed elaborator that failed recoverably is not run again while every
-- metavariable unsolved when its failing attempt began is still unsolved,
-- and the error is reported at once.
-- The stock Idris is patched for it (upstream/109-delayed-retry-doubling);
-- the type checker has the change as its own code, and this test checks
-- it.

import Prelude

%default total

export infixr 1 :&

data Got : Type -> Type -> Type where
  (:&) : (1 r : res) -> (x : a) -> Got res a

interface Machine (0 v : Type -> Type) (0 b : Type -> Type) (0 m : Type -> Type) | m where
  bind1 : (1 _ : m a) -> (1 _ : (1 _ : a) -> m c) -> m c
  pure1 : (1 _ : a) -> m a
  load  : (1 _ : b e) -> m (Got (b e) (v e))

namespace L
  export
  (>>=) : Machine v b m => (1 _ : m a) -> (1 _ : (1 _ : a) -> m c) -> m c
  (>>=) = bind1

f : Machine v b m => (1 src : b Nat) -> m (Got (b Nat) (v Nat))
f src = L.do
  (src :& b) <- load src
  (src :& x1) <- load src
  (src :& x2) <- load src
  (src :& x3) <- load src
  (src :& x4) <- load src
  (src :& x5) <- load src
  (src :& x6) <- load src
  (src :& x7) <- load src
  (src :& x8) <- load src
  (src :& x9) <- load src
  (src :& x10) <- load src
  (src :& x11) <- load src
  (src :& x12) <- load src
  (src :& x13) <- load src
  (src :& x14) <- load src
  (src :& x15) <- load src
  pure1 (the (Got (b Nat) (v Nat)) (src :& b))

main : IO ()
main = putStrLn "unreached"
