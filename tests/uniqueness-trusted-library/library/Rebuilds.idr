module Rebuilds

-- A library the frontend trusts once its table lists this package (run).
-- bump rebuilds a linear list in its own cells, so a call of it must pass
-- the list exclusive. shared passes its parameter to bump and reads it
-- again: no caller can make that call exclusive, so it is refused here,
-- in the library, whoever calls shared. once passes its parameter to bump
-- and reads it no more, so its caller's list decides.

import Linear.Notation
import Linear.List

build : Int -> LList (!* Int) -@ LList (!* Int)
build n acc = if n <= 0 then acc else build (n - 1) (MkBang n :: acc)

bump : LList (!* Int) -@ LList (!* Int)
bump [] = []
bump (MkBang x :: xs) = MkBang (x + 1) :: bump xs

sumL : Int -> LList (!* Int) -@ !* Int
sumL acc [] = MkBang acc
sumL acc (MkBang x :: xs) = sumL (acc + x) xs

shared : LList (!* Int) -> (Int, Int)
shared xs =
  let MkBang bumped = sumL 0 (bump xs)
      MkBang plain = sumL 0 xs
  in (bumped, plain)

once : LList (!* Int) -> Int
once xs = let MkBang bumped = sumL 0 (bump xs) in bumped

export
sharedOf : Int -> (Int, Int)
sharedOf n = shared (build n [])

export
onceOf : Int -> Int
onceOf n = once (build n [])
