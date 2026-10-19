-- expect: runtime closure, line 23
module Main

import Prelude

-- An implementation given as a function of a runtime value is a
-- compile-time value when the function returns one implementation at every
-- value (`Show (DPair a p)` over the Prelude's `Show (Tag n)`). This one
-- picks between two by the value, which only the running program knows.
-- near/ picks between two calls by the value, each given a function that
-- returns one implementation at every value.

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

tag : (n : Nat) -> Tag n
tag Z = Zero
tag (S k) = Next (tag k)

main : IO ()
main = do
  line <- getLine
  let n = the Nat (cast line)
  putStrLn (tagged (n ** tag n))
