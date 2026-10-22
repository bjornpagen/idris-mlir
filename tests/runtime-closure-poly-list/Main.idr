module Main

-- Polymorphic functions held in a record's field, two lambdas kept in a
-- list, each applied at a Char and at a Nat. The functions the program
-- puts in the field are a closed sum, and each use applies the member at
-- its own type.

import Prelude

record Poly where
  constructor MkPoly
  run : {0 a : Type} -> a -> List a

polys : List Poly
polys = [MkPoly (\x => [x]), MkPoly (\x => [x, x])]

main : IO ()
main = for_ polys $ \p => do
  printLn (p.run 'c')
  printLn (p.run (the Nat 3))
