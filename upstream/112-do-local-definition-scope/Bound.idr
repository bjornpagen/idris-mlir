module Bound

import Data.Vect

-- A do-bound name in a local definition's type is the bound value, as a
-- lambda's is: f takes a vector of n elements, and [1, 2] is not one, so
-- f [1, 2] does not check. Both are refused, naming the mismatch.
wrong : IO ()
wrong = do
  n <- pure (the Nat 3)
  let f : Vect n Nat -> Nat
      f v = length v
  printLn (f [1, 2])

wrongLambda : IO ()
wrongLambda = pure (the Nat 3) >>= \n =>
  let f : Vect n Nat -> Nat
      f v = length v
  in printLn (f [1, 2])
