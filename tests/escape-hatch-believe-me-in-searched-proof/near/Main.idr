module Main

import Prelude
import Data.Fin

-- The refused program with the proof found by search: its solution holds
-- what the checker unfolded of base's Fin literal, base's `believe_me`
-- among it, which is base's.

data Vals : Nat -> Type where
  Op : Fin i -> Vals i

data Names : Vals i -> Type where
  NamesAny : Names v

data Eff : Nat -> Type where
  On : (v : Vals i) -> {auto 0 named : Names v} -> Eff i

e : Eff 2
e = On (Op 0)

main : IO ()
main = case e of
  On (Op k) => printLn (finToNat k)
