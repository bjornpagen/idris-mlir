module Local

import Data.Vect

%default total

-- A typed local definition in a do block whose type names a local
-- definition an earlier let of the block defines: xs is that definition,
-- as in `let xs ... in let v ... in e`, so v's type is a vector of
-- length xs's length.
twoLets : Nat -> IO Nat
twoLets n = do
  let xs : List Nat
      xs = [n, 0]
  let v : Vect (length xs) Nat
      v = fromList xs
  pure (length v)

-- The same with both definitions in one let block, as in
-- `let xs ...; v ... in e`.
oneLet : Nat -> IO Nat
oneLet n = do
  let xs : List Nat
      xs = [n, 0]
      v : Vect (length xs) Nat
      v = fromList xs
  pure (length v)

-- After a bind, the do-bound n and the local xs in v's type.
afterBind : IO Nat
afterBind = do
  n <- pure (the Nat 3)
  let xs : List Nat
      xs = [n, 0]
  let v : Vect (length xs) Nat
      v = fromList xs
  pure (length v)
