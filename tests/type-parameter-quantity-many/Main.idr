module Main

-- Parameters whose type is a universe, taken at quantity many: an
-- interface's type family and its type, which Idris binds at quantity many
-- unless they say 0, and a type a function takes explicitly. Each is a
-- type parameter the program fixes, as an erased one is, never a value at
-- run time.

import Prelude

interface Walk (t : Type -> Type) where
  walkr : (a -> b -> b) -> b -> t a -> b

interface Measured (t : Type) where
  measure : t -> Nat

data Box a = MkBox a

Walk Box where
  walkr f z (MkBox x) = f x z

Measured String where
  measure s = length s

idT : (a : Type) -> a -> a
idT _ x = x

main : IO ()
main = do
  line <- getLine
  printLn (walkr (+) 0 (MkBox (the Nat (length line))))
  printLn (measure (idT String line))
