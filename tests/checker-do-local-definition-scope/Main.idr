module Main

-- Do blocks whose typed local definitions name, in their types, a local
-- definition an earlier `let` of the block defines (`twoLets`,
-- `afterBind`) or the same `let` block does (`oneLet`). A do block means
-- its translation into lambdas and `let ... in`, which bind a name for what
-- follows it, so a type there refers to the name and never binds it as an
-- implicit. The pinned Idris's desugaring of a do block left those names
-- out, so `xs` in `v`'s type was bound as a fresh implicit, `length ?xs`
-- was ambiguous, and each of the three was refused. In `shadowing` a
-- do-bound and a let-bound name, each also a global's, are the bound
-- values in the local types, as they were.
-- The stock Idris is patched for it (upstream/112-do-local-definition-
-- scope); the type checker has the change as its own code, and this test
-- checks it.

import Prelude
import Data.Vect

%default total

twoLets : Nat -> IO Nat
twoLets n = do
  let xs : List Nat
      xs = [n, 0]
  let v : Vect (length xs) Nat
      v = fromList xs
  pure (length v)

oneLet : Nat -> IO Nat
oneLet n = do
  let xs : List Nat
      xs = [n]
      v : Vect (length xs) Nat
      v = fromList xs
  pure (length v)

afterBind : IO Nat
afterBind = do
  n <- pure (the Nat 3)
  let xs : List Nat
      xs = [n, 0, n]
  let v : Vect (length xs) Nat
      v = fromList xs
  pure (length v)

size : Nat
size = 2

width : Nat
width = 2

shadowing : Nat -> IO Nat
shadowing k = do
  size <- pure (S k)
  let width = S size
  let v : Vect size Nat
      v = replicate size 0
  let w : Vect width Nat
      w = replicate width 0
  pure (length v + length w)

main : IO ()
main = do
  printLn !(twoLets 5)
  printLn !(oneLet 5)
  printLn !afterBind
  printLn !(shadowing 4)
