module Bind

import Data.String

-- A case on an application whose type is fixed only through a constraint
-- postponed while its arguments were checked: `given`'s `Maybe String`
-- against `?m ?a` is outside the pattern fragment until the search for
-- `Monad ?m` fails on `m` and makes it invertible, and the case reads the
-- scrutinee's type before that search is tried again.
seed : Maybe String -> Integer
seed given =
  case given >>= parseInteger of
    Just s => s
    Nothing => 0

-- The same with a function of no implicit argument: the bind alone.
parse : String -> Maybe Integer
parse = parseInteger

parsed : Maybe String -> Integer
parsed given =
  case given >>= parse of
    Just s => s
    Nothing => 0
