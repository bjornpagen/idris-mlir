module Main

import Prelude
import Linear.Notation
import Linear.List

-- Two equal literal lists, one rebuilt in place and one only read: each
-- linear list takes a fresh identity where it is made, so no merging of
-- equal values makes them one list, which the rebuild would then write
-- under the reader. The read list keeps its values.

bump : LList (!* Int) -@ LList (!* Int)
bump [] = []
bump (MkBang x :: xs) = MkBang (x + 1) :: bump xs

sumL : Int -> LList (!* Int) -@ !* Int
sumL acc [] = MkBang acc
sumL acc (MkBang x :: xs) = sumL (acc + x) xs

main : IO ()
main = do
  c <- getChar
  let k = cast (ord c - ord '0')
  let MkBang bumped = sumL k (bump [MkBang 1, MkBang 2])
  let MkBang plain = sumL k [MkBang 1, MkBang 2]
  printLn (bumped, plain)
