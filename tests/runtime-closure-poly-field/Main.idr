module Main

-- A polymorphic function held in a record's field, chosen at run time
-- between a definition and a lambda, and applied at two types by the
-- function it is passed to. The functions the program puts in the field
-- are a closed sum, and each use applies the member at its own types.

import Prelude

record Poly where
  constructor MkPoly
  run : (0 a : Type) -> a -> List a

single : (0 a : Type) -> a -> List a
single _ x = [x]

both : Poly -> (List Int, List String)
both p = (p.run Int 7, p.run String "ab")

main : IO ()
main = do
  line <- getLine
  let p = if line == "single" then MkPoly single else MkPoly (\_, x => [x, x])
  printLn (both p)
