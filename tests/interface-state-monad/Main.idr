module Main

-- A higher-kinded interface with polymorphic methods, a subclass with a
-- default method, and `do` over the user's monad: every dictionary is
-- resolved at compile time. The user's `>>=` and `>>` sit beside the
-- Prelude's; each `do` gets the one whose constraint has an implementation.

import Builtin
import Prelude

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

-- An Int from stdin: digits after an optional '-'.
readInt : IO Int
readInt = do
  c <- getChar
  if c == '-' then map negate (go 0) else if isDigit c then go (cast (ord c - 48)) else pure 0
  where
    go : Int -> IO Int
    go acc = do
      c <- getChar
      if isDigit c then go (acc * 10 + cast (ord c - 48)) else pure acc

-- prog run from the state on stdin: its result, and the state 11 past the
-- one it started from (shouts of 1, 5 and 5), in Int's wrapping arithmetic.
main : IO ()
main = do
  s0 <- readInt
  let (r, s) = run prog s0
  putStrLn (prim__cast_IntString r)
  putStrLn (prim__cast_IntString s)
