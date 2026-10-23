module Main

-- Case blocks that split a bound variable an unsolved metavariable made
-- outside the block is applied to: a record update, which is a case on the
-- record, in a lambda whose type is inferred (`bump`); the same where the
-- updated field's type is the metavariable of a `Num` the update fixes
-- (`setThreads`); and a case in a lambda applied where it is written
-- (`unitCase`, upstream's #62). Splitting the variable put each clause's
-- pattern in the metavariable's spine, outside the pattern fragment, so the
-- pinned Idris could not solve it and refused each (in `setThreads` the
-- default `Num Integer` fixed it first, against the field's `Nat`). The
-- case function now also takes the variable unsplit, which those
-- metavariables are applied to. `pick`'s case has a catch-all clause,
-- which leaves the variable as it is and solves its metavariable itself,
-- as before.
-- The stock Idris is patched for it (upstream/108-case-split-pattern-
-- fragment); the type checker has the change as its own code, and this
-- test checks it.

import Prelude

record Pool where
  constructor MkPool
  runs : List Nat

bump : List Pool -> List Pool
bump pools =
  let keep = \pool => { runs $= map S } pool
  in map keep pools

record Opts where
  constructor MkOpts
  threads : Nat

positive : Num a => Integer -> Maybe a
positive n = if n > 0 then Just (fromInteger n) else Nothing

setThreads : Opts -> Integer -> Maybe Opts
setThreads o n = map (\k => { threads := k } o) (positive n)

unitCase : ()
unitCase = (\dx => case dx of () => ()) ()

pick : Maybe Nat -> IO Nat
pick e = do Right m <- case e of
                Just v => pure (Left v)
                _ => pure (Right Z)
              | Left err => pure err
            pure m

main : IO ()
main = do
  printLn (map runs (bump [MkPool [1, 2], MkPool []]))
  printLn (map threads (setThreads (MkOpts 1) 8))
  printLn (map threads (setThreads (MkOpts 1) 0))
  printLn unitCase
  printLn !(pick (Just 3))
  printLn !(pick Nothing)
