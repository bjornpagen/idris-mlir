module Main

import Prelude

-- A record of two dictionary fields and a runtime field, read by its
-- projections from a parameter: each dictionary field holds the one
-- implementation its construction sites give it at the record's type, so
-- reading it from a runtime record is that implementation, as a match on
-- the record would bind it, whether the read or the construction site is
-- translated first.

record Ops a where
  constructor MkOps
  eqOf : Eq a
  showOf : Show a
  tag : String

describe : Ops a -> a -> a -> String
describe d x y =
  tag d ++ ": " ++ show @{showOf d} x ++
  (if (==) @{eqOf d} x y then " = " else " /= ") ++ show @{showOf d} y

mkOps : Eq a => Show a => String -> Ops a
mkOps @{e} @{s} t = MkOps e s t

main : IO ()
main = do
  x <- getLine
  y <- getLine
  putStrLn (describe (mkOps "Int") (the Int (cast x)) (cast y))
  putStrLn (describe (mkOps "String") x y)
