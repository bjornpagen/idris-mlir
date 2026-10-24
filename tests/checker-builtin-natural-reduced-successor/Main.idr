module Main

-- `%builtin Natural` on a type whose successor's type is written through
-- a definition, `Fun N`, which reduces to `N -> N`. A constructor is
-- 'Z'-like or 'S'-like by its unrestricted arguments, and the type checker
-- counted them in the type's normal form but read the argument from the
-- type as written, where `Fun N` shows none: an internal error. Both are
-- now read from the normal form, so the pragma holds, as it does for
-- `Succ : N -> N`. Checking the types is the test; the run prints the
-- naturals the type counts.

import Prelude

Fun : Type -> Type
Fun a = a -> a

data N : Type where
  Zero : N
  Succ : Fun N

%builtin Natural N

toNat : N -> Nat
toNat Zero = Z
toNat (Succ k) = S (toNat k)

main : IO ()
main = do
  printLn (toNat Zero)
  printLn (toNat (Succ (Succ (Succ Zero))))
