module Main

import Prelude
import Data.List.Elem

%default total

data Path : Nat -> Nat -> Type where
  Stay : Path x x
  Step : (t : Nat) -> Path t y -> Path x y

targets : Path x y -> List Nat
targets Stay = []
targets (Step t p) = t :: targets p

-- The predecessor of the target where the path first enters z. Matching
-- `Here` makes the erased z the runtime field t, and the leaf names z: the
-- match on t after it is a match on the variable the leaf reads as z.
before : {0 x, y, z : Nat} -> (p : Path x y) -> Elem z (targets p) -> Nat
before Stay e = absurd e
before (Step t p) Here = case t of
  Z => 0
  S k => k
before (Step t p) (There e) = before p e

-- Entered at the first, second and third target, at a target of 0 (the
-- match's Z) and above it.
main : IO ()
main = do
  printLn (before {x = 0} (Step 1 (Step 5 Stay)) (There Here))
  printLn (before {x = 0} (Step 7 Stay) Here)
  printLn (before {x = 0} (Step 0 Stay) Here)
  printLn (before {x = 0} (Step 3 (Step 0 (Step 9 Stay))) (There (There Here)))
  printLn (before {x = 0} (Step 3 (Step 0 (Step 9 Stay))) (There Here))
