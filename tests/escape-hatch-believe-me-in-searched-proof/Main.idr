-- expect: escape hatch, line 25
-- message: believe_me
module Main

import Prelude
import Data.Fin

-- `On` takes a proof, found by search, that its operand is named. The
-- operand is a Fin literal, whose bound base proves with a `believe_me` in
-- a lemma of quantity 0, which the checker unfolds into the solution of
-- the search's implicit argument: that escape hatch is base's (near/). A
-- proof the user forges with its own `believe_me` is the user's, and is
-- refused where it is written.

data Vals : Nat -> Type where
  Op : Fin i -> Vals i

data Names : Vals i -> Type where
  NamesAny : Names v

data Eff : Nat -> Type where
  On : (v : Vals i) -> {auto 0 named : Names v} -> Eff i

0 forged : Names (Op {i = 2} 0)
forged = believe_me ()

e : Eff 2
e = On (Op 0) {named = forged}

main : IO ()
main = case e of
  On (Op k) => printLn (finToNat k)
