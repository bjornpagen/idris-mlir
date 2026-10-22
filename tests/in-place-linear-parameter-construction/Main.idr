module Main

import Prelude
import Linear.Notation
import Linear.List

-- A list built where it is passed, from values read at run time, and
-- bound at quantity 1 by the function it is passed to: `twice` takes it
-- apart only through bump, so its parameter carries bump's obligation, and
-- its caller discharges it with a construction, which is made anew each
-- time it is evaluated and shared by nothing. The types alone say the
-- rebuild is in place.

bump : LList (!* Int) -@ LList (!* Int)
bump [] = []
bump (MkBang x :: xs) = MkBang (x + 1) :: bump xs

sumL : Int -> LList (!* Int) -@ !* Int
sumL acc [] = MkBang acc
sumL acc (MkBang x :: xs) = sumL (acc + x) xs

twice : (1 xs : LList (!* Int)) -> Int
twice xs = let MkBang s = sumL 0 (bump xs) in s * 2

main : IO ()
main = do
  c <- getChar
  let n = cast (ord c - ord '0')
  printLn (twice (MkBang n :: MkBang (n * 10) :: []))
