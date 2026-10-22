module Update

-- A record update in a lambda whose type is inferred (a let without a
-- signature). The update is a case on `pool`; the lambda's result type is
-- a meta applied to `pool`, which the case's clause replaces by
-- `MkPool runs`, so the clause's constraint leaves the pattern fragment.

record Pool where
  constructor MkPool
  runs : List Nat

bump : List Pool -> List Pool
bump pools =
  let keep = \pool => { runs $= map S } pool
  in map keep pools
