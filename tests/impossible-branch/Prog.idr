module Prog

import Prelude

-- The erased proof rules out Large; Idris marks that branch impossible and
-- it is never taken, also when the kind is a runtime value: the proof is
-- only had for Small, so Large never reaches size.
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
isSmall : (k : Kind) -> Maybe (IsSmall k)
isSmall Small = Just ItIs
isSmall Large = Nothing

public export
sizeOf : Kind -> Int
sizeOf k = case isSmall k of
  Just p => size k p
  Nothing => 0
