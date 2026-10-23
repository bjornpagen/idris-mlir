module Literal

-- A scrutinee whose type only a default fixes: the literal's `Num ?a`
-- waits for `%defaulthint`, which runs after the case is elaborated. No
-- constraint fixes it, so the case still cannot be built.
small : Bool
small = case 3 of
          0 => True
          _ => False
