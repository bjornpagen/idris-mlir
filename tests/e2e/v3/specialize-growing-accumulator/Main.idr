module Main

-- rule: ELIM-SPEC-1, OPT-PIPE-5
-- `count` is called with a counter read at runtime and an accumulator that
-- is a constant, and grows by 3 at every call: specializing on it would
-- clone `count` forever, once per value, since the counter never becomes
-- known. The clone limit (--idr-clone-limit, docs/cutover.md 6.3) stops it:
-- the program compiles, the calls past the limit run the original, and the
-- result is what the source says. (Idris proves no loop on an Int
-- terminating, so `count` is partial; a total loop needs a Nat or a list as
-- its counter, which cannot exist at runtime in this profile.)

import Prelude

count : Int -> Int -> Int
count 0 acc = acc
count k acc = count (k - 1) (acc + 3)

main : IO ()
main = do
  c <- getChar
  let n = the Int (cast (ord c) - 48)
  printLn (count (n * 1000) 0)
