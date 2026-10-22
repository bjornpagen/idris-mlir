module Covering

import Data.List.Elem

%default total

data Kind = Read | Write | Allocate | Free

-- Covering: a proof that Read is the second element is There Here, which
-- would need Read = Write, so the third clause covers what the first two
-- leave of k = Read.
f : (k : Kind) -> Elem k [Read, Write] -> ()
f Read Here = ()
f Write (There Here) = ()
f _ (There (There later)) = absurd later
