module Main

-- rule: FE-TR-6, ELIM-G-2, ELIM-G-3
-- A higher-kinded interface with polymorphic methods, a subclass with a
-- default method, and `do` over the user's monad: every dictionary is
-- resolved at compile time.

import Builtin
import IdrisMLIR.IO

record St s a where
  constructor MkSt
  run : s -> (a, s)

interface Mnd m where
  ret : a -> m a
  bind : m a -> (a -> m b) -> m b

Mnd (St s) where
  ret x = MkSt (\s => (x, s))
  bind (MkSt f) k = MkSt (\s => let (a, s') = f s in run (k a) s')

interface Mnd m => Loud m where
  shout : Int -> m ()
  twice : Int -> m ()
  twice n = bind (shout n) (\_ => shout n)

Loud (St Int) where
  shout n = MkSt (\s => ((), prim__add_Int s n))

(>>=) : Mnd m => m a -> (a -> m b) -> m b
(>>=) = bind

(>>) : Mnd m => m () -> Lazy (m b) -> m b
a >> b = bind a (\_ => b)

five : Int
five = 5

prog : St Int Int
prog = do
  shout 1
  x <- ret five
  twice x
  ret x

main : IO ()
main = let (r, s) = run prog 100 in do
  putStrLn (prim__cast_IntString r)
  putStrLn (prim__cast_IntString s)
