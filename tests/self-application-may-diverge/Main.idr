module Main

-- A type that is not strictly positive, D, whose one constructor holds a
-- function from D itself, lets selfApply loop without naming itself:
-- `selfApply (MkD selfApply)` applies selfApply to its own wrapping for
-- ever. Idris accepts the program under its default, covering, and does
-- not prove selfApply to end: its checker finds D not strictly positive,
-- and so neither selfApply nor anything that calls it terminating. The
-- looping call's value is unused, and evaluation is eager, so it runs
-- where evaluation reaches it, here only on the input 9, which this test
-- does not give.

import Prelude

data D = MkD (D -> Nat)

selfApply : D -> Nat
selfApply (MkD f) = f (MkD f)

main : IO ()
main = do
  c <- getChar
  if c == '9'
    then do let n = selfApply (MkD selfApply)
            putStrLn "never printed"
    else putStrLn "not taken"
