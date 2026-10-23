module Main

-- Two polymorphic functions held in records' fields, each applied where it
-- is held: one over a functor at Int, used at Maybe, and one over an
-- element type and a functor, used at List. Every use of a polymorphic
-- function held at run time shares the positions of the application, so
-- at one position the first use gives a Functor dictionary and the second
-- a type constructor; each function held reads that position at its own
-- kind, a dictionary or a family.

import Prelude

record Bump where
  constructor MkBump
  bump : {0 f : Type -> Type} -> Functor f => f Int -> f Int

record Same where
  constructor MkSame
  same : {0 a : Type} -> {0 g : Type -> Type} -> Functor g => g a -> g a

inc : {0 f : Type -> Type} -> Functor f => f Int -> f Int
inc xs = map (+ 1) xs

keep : {0 a : Type} -> {0 g : Type -> Type} -> Functor g => g a -> g a
keep xs = map id xs

main : IO ()
main = do
  printLn ((MkBump inc).bump (Just 1))
  printLn ((MkSame keep).same [1, 2])
