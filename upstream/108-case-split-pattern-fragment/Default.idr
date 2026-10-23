module Default

-- The case on e has a catch-all clause, which leaves e as it is: there the
-- type of the case, a meta applied to e, is in the pattern fragment, and
-- the clause solves it.

f : Maybe Nat -> IO Nat
f e = do Right m <- case e of
             Just v => pure (Left v)
             _ => pure (Right Z)
           | Left err => pure err
         pure m
