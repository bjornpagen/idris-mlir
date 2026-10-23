module Main

-- A record update of a variable whose type is known, in a let without a
-- signature. The let's type is an unknown applied to `b`, which only the
-- case after it fixes; the case splits `b` in its first clause, where that
-- unknown stands applied to `True` and cannot be solved, and that clause's
-- own update of `st'` needs a record before the catch-all, which leaves
-- `b` as it is, is checked. `st`'s own type names the record, so the
-- update of `st` is a case on `st` at once. Checking the types is the
-- test; the run prints each branch's flag.

import Prelude

record S where
  constructor MkS
  flag : Bool

step : S -> Bool -> S
step st b =
  let st' = { flag := True } st
  in case b of
       True => { flag := False } st'
       _ => st'

main : IO ()
main = do
  printLn (flag (step (MkS False) True))
  printLn (flag (step (MkS False) False))
