module Main

-- An ambiguous `empty` (`Box.empty`, `Names.empty` and the prelude's
-- `Alternative` one) as a fold's start in a let's value whose step is a
-- case block, with `let ... in` and with a do block's `let`, its
-- translation. The name waits, delayed, until its type is known, and the
-- let's value runs its case blocks first; the pinned Idris put back only
-- the delayed elaborators from before the value, so the name's was lost
-- once a case block was retried, and refused each for an unsolved
-- `delayed` hole. The ones a let's value does not run now stay delayed
-- for the retries around it, so the name is resolved by its type, `Box`,
-- as on a right-hand side.
-- The stock Idris is patched for it (upstream/114-let-delayed-elaborator-
-- dropped); the type checker has the change as its own code, and this
-- test checks it.

import Prelude

%default total

namespace Box
  public export
  data Box = MkBox (List Nat)

  public export
  empty : Box
  empty = MkBox []

  public export
  put : Nat -> Box -> Box
  put n (MkBox ns) = MkBox (n :: ns)

namespace Names
  public export
  empty : List String
  empty = []

lets : List Nat -> Box
lets ns =
  let box = the Box (foldr (\n => case n of
                                    S k => put k
                                    Z => id) empty ns) in
  box

doLet : List Nat -> IO Box
doLet ns = do
  let box = the Box (foldr (\n => case n of
                                    S k => put k
                                    Z => id) empty ns)
  pure box

contents : Box -> List Nat
contents (MkBox ns) = ns

main : IO ()
main = do
  printLn (contents (lets [1, 0, 3]))
  box <- doLet [2, 5]
  printLn (contents box)
