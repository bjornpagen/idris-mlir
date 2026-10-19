-- expect: runtime closure, line 22
-- message: an implementation chosen at runtime
module Main

import Prelude

-- An implementation given as a function of a runtime value is a
-- compile-time value when the function returns one implementation at every
-- value (`Show (DPair a p)` over the Prelude's `Show (Tag n)`). This one
-- picks between two by the value, which only the running program knows.

data Tag : Nat -> Type where
  Zero : Tag Z
  Next : Tag n -> Tag (S n)

[loud] Show (Tag n) where
  show _ = "LOUD"

[quiet] Show (Tag n) where
  show _ = "quiet"

describe : ({y : Nat} -> Show (Tag y)) => DPair Nat Tag -> String
describe (y ** t) = show t

tagged : DPair Nat Tag -> String
tagged = describe @{\{y} => if y == 0 then loud else quiet}

main : IO ()
main = do
  line <- getLine
  putStrLn (tagged (Z ** Zero))
