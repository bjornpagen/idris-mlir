module NoneFits

namespace Box
  public export
  data Box = MkBox (List Nat)

  public export
  empty : Box
  empty = MkBox []

namespace Names
  public export
  empty : List String
  empty = []

-- No `empty` is a `Bool`. In a let's value the name is refused as it is
-- on a right-hand side, where its delayed elaboration runs and says why.
inLet : List Nat -> Bool
inLet ns =
  let flag = the Bool (foldr (\n => case n of
                                      S k => not
                                      Z => id) empty ns) in
  flag

onRight : List Nat -> Bool
onRight ns =
  the Bool (foldr (\n => case n of
                           S k => not
                           Z => id) empty ns)
