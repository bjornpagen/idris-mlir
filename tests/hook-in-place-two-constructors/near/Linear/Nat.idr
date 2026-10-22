module Linear.Nat

-- One constructor that holds fields, the cell each rebuild takes.
public export
data LNat : Type where
  Zero : LNat
  Succ : LNat -> LNat
