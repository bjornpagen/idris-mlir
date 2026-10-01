||| Linear naturals: a natural whose every successor is used exactly once,
||| as upstream's `Data.Linear.LNat` has them.
module Linear.Nat

import Linear.Notation

%default total

public export
data LNat : Type where
  Zero : LNat
  Succ : LNat -@ LNat

||| The natural it is, at the type level: a linear value cannot feed `S`.
public export
0 toNat : LNat -@ Nat
toNat Zero = Z
toNat (Succ n) = S (toNat n)

||| The sum, in the cells of its first operand.
export
add : LNat -@ LNat -@ LNat
add Zero x = x
add (Succ v) x = Succ (add v x)
