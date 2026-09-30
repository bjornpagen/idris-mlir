-- A match on a linear value whose catch-all names the value: the match
-- uses it once, and the catch-all returns what the match used.
module Main
import Prelude

data T : Type where
  L : T
  N : (1 l : T) -> Int -> T

data C = MkC Int

sz : (1 t : T) -> Int -> C
sz L acc = MkC acc
sz (N l k) acc = sz l (acc + k)

-- a case on a linear binder with a catch-all that names the scrutinee
f : (1 t : T) -> T
f t = case t of
        N l k => N (f l) (k + 1)
        t' => t'

build : Int -> T
build n = if n <= 0 then L else N (build (n - 1)) n

main : IO ()
main = do
  n <- pure 10
  let MkC c = sz (f (build n)) 0
  printLn c
