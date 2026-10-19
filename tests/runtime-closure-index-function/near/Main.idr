module Main

import Prelude

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
tagged p = if fst p == 0 then describe @{\{y} => loud} p else describe @{\{y} => quiet} p

tag : (n : Nat) -> Tag n
tag Z = Zero
tag (S k) = Next (tag k)

main : IO ()
main = do
  line <- getLine
  let n = the Nat (cast line)
  putStrLn (tagged (n ** tag n))
