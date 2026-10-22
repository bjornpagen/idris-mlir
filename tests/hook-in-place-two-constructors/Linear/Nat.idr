module Linear.Nat

-- Two constructors that hold fields, where the promise needs one.
public export
data LNat : Type where
  Zero : LNat
  Succ : LNat -> LNat
  Twice : LNat -> LNat
