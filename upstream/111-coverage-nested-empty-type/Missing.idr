module Missing

import Data.Nat

%default total

-- A case that is missing: `(S Z, (n, LTESucc LTEZero))` is a value the
-- clause does not match. The search must not find its type empty.
below : (c : Nat) -> (Nat, LTE c 1) -> Bool
below _ (_, LTEZero) = True

data Head = MkHead (Maybe Nat) (List Nat)

-- A case that is missing though an equation in its argument holds of the
-- part beside it: `MkHead Nothing [t]`, whose pair is `([t] ** (Refl,
-- LTESucc LTEZero))`. Read under `ts = t :: _` the bound still has a
-- value, and the search must not find the type empty.
upToOne : (r : Head) -> (ts : List Nat ** (r = MkHead Nothing ts, LTE (length ts) 1)) -> Bool
upToOne (MkHead Nothing []) ([] ** (Refl, _)) = True
