-- expect: elaboration, line 34
-- message: Undefined name j
module Main

-- `(x ** p)`, with no type written for `x`, is upstream's alternative
-- between the dependent pair type `DPair _ (\x => p)`, `x` bound over `p`,
-- and the dependent pair `MkDPair x p`, the pair its default. Where the
-- type the site is expected to have is not known, both readings are
-- elaborated, and a reading that refers to an undefined name ends the
-- choice with that error. `j` names nothing here, so the pair's reference
-- to it refuses the site, though the type would bind a `j` of its own.

import Prelude

%default total

data Tag : Nat -> Type where
  MkTag : (n : Nat) -> Tag n

interface Reading t where
  which : (0 _ : t) -> String

Reading Type where
  which _ = "the dependent pair type"

Reading (n : Nat ** Type) where
  which _ = "the dependent pair"

-- `which`'s argument may be of any type: the site's expected type is not
-- known.
unbound : String
unbound =
  which
    (j ** Tag j)

main : IO ()
main = putStrLn unbound
