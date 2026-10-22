module Main

-- A polymorphic function taken out of a record's field by a match and put
-- back in a lambda that applies it, once and twice over, then applied at
-- a Char and at a Nat.

import Prelude

record Poly where
  constructor MkPoly
  run : {0 a : Type} -> a -> List a

singles : Poly
singles = MkPoly (\x => [x])

wrap : Poly -> Poly
wrap (MkPoly f) = MkPoly (\x => f x)

main : IO ()
main = do
  printLn ((wrap singles).run 'z')
  printLn ((wrap (wrap singles)).run (the Nat 2))
