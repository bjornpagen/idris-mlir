module Prog

-- The erased proof rules out Large; Idris marks that branch impossible and
-- it is never taken.
public export
data Kind = Small | Large

public export
data IsSmall : Kind -> Type where
  ItIs : IsSmall Small

public export
size : (k : Kind) -> (0 _ : IsSmall k) -> Int
size Small _ = 17
size Large ItIs impossible

public export
main : Int
main = size Small ItIs
