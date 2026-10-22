module Hint

import Data.String

-- k's type is the meta `a` of parsePositive's `Num a`; the record update is a
-- case on `o`, inside which `a` stands applied to `MkOpts t`, so `a = Nat`
-- is postponed and the default hint `Num Integer` fires first.

record Opts where
  constructor MkOpts
  threads : Nat

setThreads : Opts -> String -> Maybe Opts
setThreads o n = map (\k => { threads := k } o) (parsePositive n)
