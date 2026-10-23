module Catchall

-- A record update of a variable whose type is known, in a let without a
-- signature. The update waits for the let's type, a meta applied to `b`,
-- which only the case after it fixes; the case splits `b` in its first
-- clause, where that meta stands applied to `True` and cannot be solved,
-- and that clause's own update of `st'` needs it before the catch-all,
-- which leaves `b` as it is, is checked.

record S where
  constructor MkS
  flag : Bool

step : S -> Bool -> S
step st b =
  let st' = { flag := True } st
  in case b of
       True => { flag := False } st'
       _ => st'
