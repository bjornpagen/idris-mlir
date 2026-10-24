module Main

-- A refutation read out of a decision whose erased indices are index levels
-- of its function, passed into a case block: `h`'s `x` and `y` are erased
-- and named only inside `Dec (x = y)`, so they are `h`'s index levels, and
-- `Dec`'s family takes the indices of `x = y` as its own, so `contra` refutes
-- `x = y` at those levels, as the case block takes it.

import Prelude
import Decidable.Equality

h : {0 x, y : Nat} -> Dec (x = y) -> Bool -> Bool
h (Yes Refl) b = b
h (No contra) b = case b of
  True => let k : Not (x = y)
              k = contra in False
  False => True

main : IO ()
main = printLn (h {x = 1} {y = 2} (decEq 1 2) True)
