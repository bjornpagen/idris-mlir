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

-- The path up to where it first enters z. Matching `Here` makes the erased
-- z the runtime field t.
upTo : {0 x, y, z : Nat} -> (p : Path x y) -> Elem z (targets p) -> Path x z
upTo Stay e = absurd e
upTo (Step t p) Here = Step t Stay
upTo (Step t p) (There e) = Step t (upTo p e)

-- The path cut where it enters its first, second and third target: what
-- is left are the targets up to that one.
main : IO ()
main = do
  printLn (length (targets (upTo {x = 0} (Step 1 (Step 2 Stay)) (There Here))))
  printLn (targets (upTo {x = 0} (Step 1 (Step 2 Stay)) (There Here)))
  printLn (targets (upTo {x = 0} (Step 4 Stay) Here))
  printLn (targets (upTo {x = 0} (Step 1 (Step 2 (Step 3 Stay))) (There (There Here))))
  printLn (targets (upTo {x = 0} (Step 1 (Step 2 (Step 3 Stay))) Here))
