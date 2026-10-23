module Shadow

import Data.Vect

%default total

size : Nat
size = 2

width : Nat
width = 2

-- A do-bound and a let-bound name, each also a global's, in a local
-- definition's type: each is the bound value, which the elaborator finds
-- in scope, so no implicit is bound and none is warned of.
bound : Nat -> IO Nat
bound k = do
  size <- pure (S k)
  let width = S size
  let v : Vect size Nat
      v = replicate size 0
  let w : Vect width Nat
      w = replicate width 0
  pure (length v + length w)
