module Generalised

-- An implicit argument no constraint relates is still bound as an
-- argument of the type: the element type of `tagged`'s empty list, so
-- that it takes a `Tag []` of any element type.

data Tag : List a -> Type where
  MkTag : Tag xs

0 tagged : Tag [] -> ()
tagged _ = ()

0 both : (Tag {a = Nat} [] -> (), Tag {a = String} [] -> ())
both = (tagged, tagged)
