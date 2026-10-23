module Main

-- A type taken at quantity many is a type parameter: every instance of f
-- knows its type, so f's match on it chooses its alternative when the
-- program is compiled. Each kind of head a type has is matched: a type
-- constructor, a primitive type, Type, a function type, and a type
-- constructor whose argument the alternative binds and recurs on; a type
-- no alternative names takes the default.

import Prelude

f : Type -> Nat
f Nat = 1
f Int = 2
f Type = 3
f (Nat -> Nat) = 4
f (List a) = 5 + f a
f _ = 0

main : IO ()
main = do
  printLn (f Nat)
  printLn (f Bool)
  printLn (f Int)
  printLn (f String)
  printLn (f Type)
  printLn (f (Nat -> Nat))
  printLn (f (Bool -> Nat))
  printLn (f (List Nat))
  printLn (f (List (List Int)))
  printLn (f (Maybe Nat))
