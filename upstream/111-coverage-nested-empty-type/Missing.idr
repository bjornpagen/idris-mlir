module Missing

import Data.Nat

%default total

-- A case that is missing: `(S Z, (n, LTESucc LTEZero))` is a value the
-- clause does not match. The search must not find its type empty.
below : (c : Nat) -> (Nat, LTE c 1) -> Bool
below _ (_, LTEZero) = True
