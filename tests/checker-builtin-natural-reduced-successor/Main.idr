-- expect: pragma, line 25
-- message: %builtin
module Main

-- `%builtin Natural N` on a type whose successor's type is written through
-- a definition, `Fun N`, which reduces to `N -> N`. A constructor is
-- 'Z'-like or 'S'-like by its unrestricted arguments, and the type checker
-- counted them in the type's normal form but read the argument from the
-- type as written, where `Fun N` shows none: an internal error. Both are
-- now read from the normal form, so the checker elaborates the pragma as
-- it does for `Succ : N -> N`. What the pragma means past the checker is
-- a back end's representation of `N`, which this compiler decides from the
-- program, so the program is refused at the pragma; that refusal is its
-- only error, where the checker stopped before.

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
