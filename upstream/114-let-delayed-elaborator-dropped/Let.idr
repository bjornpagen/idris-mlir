module Let

-- Two definitions named `empty` beside the prelude's `Alternative` one, so
-- that `empty` is ambiguous and its elaboration waits until its type is
-- known.
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

-- The ambiguous `empty` as a fold's start in a let's value, the fold's
-- step a case block: with `let ... in`, and with a do block's `let`,
-- which is its translation.
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
