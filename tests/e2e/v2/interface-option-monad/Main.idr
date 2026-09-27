module Main

-- rule: PROF-IFACE-1, FE-TR-6, ELIM-G-2, ELIM-G-3
-- A Functor/Applicative/Monad hierarchy over a user option type; `do` in
-- `calc` uses the user's `>>=` (the Prelude's would need a `Monad Opt`),
-- and `main`'s uses the Prelude's, for IO.

import Builtin
import Prelude

data Opt a = None | Some a

interface Fun f where
  fmap : (a -> b) -> f a -> f b

interface Fun f => Apl f where
  pure' : a -> f a
  ap : f (a -> b) -> f a -> f b

interface Apl m => Mon m where
  bind : m a -> (a -> m b) -> m b

Fun Opt where
  fmap f None = None
  fmap f (Some x) = Some (f x)

Apl Opt where
  pure' = Some
  ap (Some f) (Some x) = Some (f x)
  ap _ _ = None

Mon Opt where
  bind None _ = None
  bind (Some x) k = k x

(>>=) : Mon m => m a -> (a -> m b) -> m b
(>>=) = bind

nonNegative : Int -> Opt Int
nonNegative n = case prim__lt_Int n 0 of
  0 => Some n
  _ => None

calc : Int -> Int -> Int -> Opt Int
calc a b c = do
  x <- nonNegative (prim__sub_Int a b)
  y <- nonNegative (prim__sub_Int x c)
  pure' (prim__add_Int x y)

report : Opt Int -> IO ()
report None = putStrLn "none"
report (Some n) = putStrLn (prim__cast_IntString n)

main : IO ()
main = do
  report (calc 100 5 2)
  report (calc 1 5 2)
  report (fmap (prim__mul_Int 2) (calc 100 5 2))
  report (calc 10 3 8)
